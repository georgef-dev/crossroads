// The model the UI draws. Ported from the snapshot shape in omarchy/plugin/Model.js.
//
// On Omarchy the snapshot is JSON from `crossroads fetch`, so the plugin
// validates and bounds untrusted command output. The Mac has no such command:
// EventKit hands back typed objects and Gmail's JSON is decoded where it is
// fetched. The bounds still apply here, because a very large account should
// never make the panel unusable.

import Foundation

/// At most this many events reach the view.
public let maxEvents = 500
/// At most this many mail messages, or errors, reach the view.
public let maxMail = 50

/// One event as the view shows it: the event, the kind of overlap it has, and
/// the calendar's name for display and search.
public struct FlaggedEvent: Hashable, Sendable {
    public let event: Event
    public let kind: Kind
    public let calendarName: String

    public init(event: Event, kind: Kind, calendarName: String) {
        self.event = event
        self.kind = kind
        self.calendarName = calendarName
    }
}

/// One reminder as the view shows it, with the kind of clash it has.
public struct FlaggedReminder: Hashable, Sendable {
    public let reminder: Reminder
    public let kind: Kind

    public init(reminder: Reminder, kind: Kind) {
        self.reminder = reminder
        self.kind = kind
    }
}

/// One overlap card: the two events that collide, and the time they share.
public struct OverlapCard: Hashable, Sendable {
    public let events: [FlaggedEvent]
    public let start: Date
    public let end: Date
    public let kind: Kind

    public init(events: [FlaggedEvent], start: Date, end: Date, kind: Kind) {
        self.events = events
        self.start = start
        self.end = end
        self.kind = kind
    }
}

public struct MailMessage: Hashable, Sendable {
    public let id: String
    public let subject: String
    public let sender: String
    public let account: String
    public let received: Date
    public let link: String

    public init(
        id: String,
        subject: String,
        sender: String,
        account: String,
        received: Date = .distantPast,
        link: String
    ) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.account = account
        self.received = received
        self.link = link
    }
}

/// Everything the view draws, from one fetch.
public struct Snapshot: Hashable, Sendable {
    public let fetchedAt: Date?
    public let events: [FlaggedEvent]
    public let overlaps: [OverlapCard]
    /// The reminders that need attention, soonest first.
    public let reminders: [FlaggedReminder]
    public let mail: [MailMessage]
    /// What went wrong, per source, so one broken source doesn't hide the others.
    public let errors: [String]

    public init(
        fetchedAt: Date? = nil,
        events: [FlaggedEvent] = [],
        overlaps: [OverlapCard] = [],
        reminders: [FlaggedReminder] = [],
        mail: [MailMessage] = [],
        errors: [String] = []
    ) {
        self.fetchedAt = fetchedAt
        self.events = Array(events.prefix(maxEvents))
        self.overlaps = Array(overlaps.prefix(maxEvents))
        self.reminders = Array(reminders.prefix(maxEvents))
        self.mail = Array(mail.prefix(maxMail))
        self.errors = Array(errors.prefix(maxMail))
    }
}

/// The snapshot for what one fetch found: every event with the kind the rules
/// give it, one card per collision, and the mail newest first.
/// Ported from omarchy/src/crossroads/snapshot.py.
public func buildSnapshot(
    fetchedAt: Date? = nil,
    events: [Event],
    reminders: [Reminder] = [],
    now: Date = .now,
    calendar: Calendar = .current,
    calendarNames: [String: String] = [:],
    mail: [MailMessage] = [],
    errors: [String] = []
) -> Snapshot {
    func name(of event: Event) -> String {
        calendarNames[event.calendar] ?? event.calendar
    }

    // Only the reminders that need attention reach the view, but every one of
    // them can still flag an event, so the kinds see all of them.
    let needingAttention = remindersNeedingAttention(reminders, now: now, calendar: calendar)

    // Kinds are worked out over every fetched event, before the list is capped.
    let flagged = zip(events, classify(events, reminders: reminders))
        .map { FlaggedEvent(event: $0, kind: $1, calendarName: name(of: $0)) }
        .sorted { $0.event.start < $1.event.start }

    let cards = overlaps(events)
        .sorted { $0.start < $1.start }
        .map { overlap -> OverlapCard in
            // A card is personal + work when its two events disagree.
            let kind: Kind = overlap.first.tag == overlap.second.tag ? .same : .mixed
            return OverlapCard(
                events: [overlap.first, overlap.second].map {
                    FlaggedEvent(event: $0, kind: kind, calendarName: name(of: $0))
                },
                start: overlap.start,
                end: overlap.end,
                kind: kind
            )
        }

    let flaggedReminders = zip(
        needingAttention,
        classifyReminders(needingAttention, events: events)
    ).map { FlaggedReminder(reminder: $0, kind: $1) }

    return Snapshot(
        fetchedAt: fetchedAt,
        events: flagged,
        overlaps: cards,
        reminders: flaggedReminders,
        mail: mail.sorted { $0.received > $1.received },
        errors: errors
    )
}
