// Calendars and reminders, read from the Mac through EventKit.
//
// Everything here is the thin part: it reads fields off EventKit's objects and
// hands them to CrossroadsCore, which decides what they mean. That split is
// what lets the rules be tested without a real account.
//
// The store is used on the main actor. EKEventStore is not Sendable, and a
// local fetch over a two-week window is quick, so this keeps the concurrency
// simple rather than fast. Worth revisiting if a refresh ever feels slow.

import EventKit
import Foundation

import CrossroadsCore

@MainActor
final class EventKitSource {
    private let store = EKEventStore()

    enum Access {
        case granted
        case denied
        case failed(String)
    }

    /// Asks for calendars and reminders separately, so one refusal does not
    /// hide the other source.
    func requestAccess() async -> (events: Access, reminders: Access) {
        let events = await request { try await self.store.requestFullAccessToEvents() }
        let reminders = await request { try await self.store.requestFullAccessToReminders() }
        return (events, reminders)
    }

    private func request(_ ask: () async throws -> Bool) async -> Access {
        do {
            return try await ask() ? .granted : .denied
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Every calendar the Mac can see, and every reminder list, so the settings
    /// can offer each one. Reminder lists are calendars too, as far as
    /// EventKit is concerned.
    func calendars() -> [CalendarInfo] {
        let all = store.calendars(for: .event) + store.calendars(for: .reminder)
        return all.map {
            CalendarInfo(
                id: $0.calendarIdentifier,
                name: $0.title,
                source: $0.source?.title ?? ""
            )
        }
    }

    /// The names to show for each calendar, keyed the way events refer to them.
    func calendarNames() -> [String: String] {
        Dictionary(
            calendars().map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The events from `now` through the end of the widest range, on the
    /// calendars the settings have switched on.
    func events(from now: Date, days: Int, settings: Settings, calendar: Calendar = .current) -> [Event] {
        let wanted = store.calendars(for: .event).filter {
            settings.setting(for: $0.calendarIdentifier) != .off
        }
        guard !wanted.isEmpty else { return [] }

        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days + 1, to: start) ?? now
        let found = store.events(
            matching: store.predicateForEvents(withStart: start, end: end, calendars: wanted)
        )

        return CrossroadsCore.events(from: found.map(fields(of:))) {
            settings.setting(for: $0)
        }
    }

    /// Open reminders on the lists the settings have switched on. Everything
    /// open is fetched, not only what needs attention, because a reminder due
    /// later can still clash with an event in range.
    func reminders(settings: Settings, calendar: Calendar = .current) async -> [Reminder] {
        let wanted = store.calendars(for: .reminder).filter {
            settings.setting(for: $0.calendarIdentifier) != .off
        }
        guard !wanted.isEmpty else { return [] }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: wanted
        )

        // EKReminder is not Sendable, so the mapping happens inside the
        // handler and only our own values cross back.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                let mapped = (found ?? []).compactMap {
                    reminder(from: $0, settings: settings, calendar: calendar)
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    // ---- Reading EventKit's objects.

    private func fields(of event: EKEvent) -> CalendarEventFields {
        CalendarEventFields(
            uid: event.calendarItemExternalIdentifier ?? "",
            occurrence: event.occurrenceDate,
            calendarIdentifier: event.calendar.calendarIdentifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            state: state(of: event),
            response: myResponse(to: event),
            link: event.url?.absoluteString ?? ""
        )
    }

    private func state(of event: EKEvent) -> EventState {
        switch event.status {
        case .canceled: .canceled
        case .tentative: .tentative
        default: .confirmed
        }
    }

    /// Your own answer, when you are an attendee at all. A plain busy block
    /// has no attendees, and so no answer.
    private func myResponse(to event: EKEvent) -> Response? {
        guard let me = event.attendees?.first(where: \.isCurrentUser) else { return nil }
        switch me.participantStatus {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        default: return .pending
        }
    }

}

/// Reading one reminder, outside the main actor, so it can run in EventKit's
/// own completion handler. A reminder on a list that is off is dropped.
private func reminder(
    from reminder: EKReminder,
    settings: Settings,
    calendar: Calendar
) -> Reminder? {
    guard let tag = settings.setting(for: reminder.calendar.calendarIdentifier).tag else {
        return nil
    }
    let components = reminder.dueDateComponents
    return Reminder(
        id: reminder.calendarItemIdentifier,
        list: reminder.calendar.calendarIdentifier,
        tag: tag,
        title: reminder.title ?? "",
        due: components.flatMap { calendar.date(from: $0) },
        // A due date with no time of day cannot clash with anything.
        hasTime: components?.hour != nil,
        isCompleted: reminder.isCompleted,
        link: ""
    )
}
