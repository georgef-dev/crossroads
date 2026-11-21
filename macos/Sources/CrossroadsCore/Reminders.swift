// Reminders: which ones need attention, and when one clashes with an event.
// Spec: specs/ConflictFlags.tla.
//
// A reminder is an instant, not a stretch of time, so it cannot overlap
// anything. It clashes with an event when its due time falls inside that
// event, and only with events, never with another reminder.

import Foundation

public struct Reminder: Hashable, Sendable {
    public let id: String
    /// The reminder list it sits on. Lists carry a tag, as calendars do.
    public let list: String
    public let tag: Tag
    public let title: String
    /// Nothing when the reminder has no due date at all.
    public let due: Date?
    /// A due date with no time of day cannot clash with anything.
    public let hasTime: Bool
    public let isCompleted: Bool
    public let link: String

    public init(
        id: String,
        list: String,
        tag: Tag,
        title: String,
        due: Date? = nil,
        hasTime: Bool = false,
        isCompleted: Bool = false,
        link: String = ""
    ) {
        self.id = id
        self.list = list
        self.tag = tag
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.isCompleted = isCompleted
        self.link = link
    }
}

/// Whether a reminder is due during an event. The event's start counts and its
/// end does not, the same half-open window the overlap rule uses.
public func clash(_ reminder: Reminder, _ event: Event) -> Bool {
    guard !reminder.isCompleted, reminder.hasTime, let due = reminder.due else { return false }
    guard !event.isAllDay, event.status.isActive else { return false }
    return event.start <= due && due < event.end
}

/// The kind of each reminder, in the same order as the input.
public func classifyReminders(_ reminders: [Reminder], events: [Event]) -> [Kind] {
    reminders.map { reminder in
        let clashing = events.filter { clash(reminder, $0) }
        if clashing.contains(where: { $0.tag != reminder.tag }) { return .mixed }
        return clashing.isEmpty ? .none : .same
    }
}

/// The reminders that need attention: still open, with a due date, and due no
/// later than the end of today. That is everything overdue plus everything due
/// today, soonest first.
public func remindersNeedingAttention(
    _ reminders: [Reminder],
    now: Date,
    calendar: Calendar = .current
) -> [Reminder] {
    let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        ?? now
    return reminders
        .filter { !$0.isCompleted }
        .filter { guard let due = $0.due else { return false }; return due < endOfToday }
        .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
}
