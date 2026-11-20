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
    public let link: String

    public init(id: String, subject: String, sender: String, account: String, link: String) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.account = account
        self.link = link
    }
}

/// Everything the view draws, from one fetch.
public struct Snapshot: Hashable, Sendable {
    public let fetchedAt: Date?
    public let events: [FlaggedEvent]
    public let overlaps: [OverlapCard]
    public let mail: [MailMessage]
    /// What went wrong, per source, so one broken source doesn't hide the others.
    public let errors: [String]

    public init(
        fetchedAt: Date? = nil,
        events: [FlaggedEvent] = [],
        overlaps: [OverlapCard] = [],
        mail: [MailMessage] = [],
        errors: [String] = []
    ) {
        self.fetchedAt = fetchedAt
        self.events = Array(events.prefix(maxEvents))
        self.overlaps = Array(overlaps.prefix(maxEvents))
        self.mail = Array(mail.prefix(maxMail))
        self.errors = Array(errors.prefix(maxMail))
    }
}
