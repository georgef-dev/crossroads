// Turning a calendar event from the system into the event the rules work on.
//
// The mapping is pure, and takes plain fields rather than an EKEvent, so it is
// tested against recorded shapes without EventKit or a real account. The thin
// part that reads those fields off an EKEvent lives in the app.
//
// Ported from event_from_google in omarchy/src/crossroads/google.py, so both
// platforms decide an event's identity and status the same way.

import Foundation

/// A free/busy event carries no title of its own.
public let busyTitle = "Busy"

/// What the calendar says about the event itself, apart from who answered.
public enum EventState: String, Codable, Sendable {
    case confirmed
    case tentative
    case canceled
}

/// What you answered, when you are an attendee at all.
public enum Response: String, Codable, Sendable {
    case accepted
    case declined
    case tentative
    case pending
}

/// The fields Crossroads reads from one event on one calendar.
public struct CalendarEventFields: Hashable, Sendable {
    /// EventKit's `calendarItemExternalIdentifier`: the iCalendar UID. Copies
    /// of one meeting on two calendars share it, which is what keeps an event
    /// from conflicting with itself.
    public var uid: String
    /// Which instance of a repeating event this is, so two of them are not
    /// taken for the same event. Nil for an event that does not repeat.
    public var occurrence: Date?
    public var calendarIdentifier: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var state: EventState
    /// Your own answer, or nil when the event has no attendees.
    public var response: Response?
    public var link: String

    public init(
        uid: String,
        occurrence: Date? = nil,
        calendarIdentifier: String,
        title: String = "",
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        state: EventState = .confirmed,
        response: Response? = nil,
        link: String = ""
    ) {
        self.uid = uid
        self.occurrence = occurrence
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.state = state
        self.response = response
        self.link = link
    }
}

/// The event the rules work on, or nothing when the calendar has withdrawn it.
/// A cancelled event is dropped rather than carried with a status, exactly as
/// the Omarchy fetcher drops it.
public func event(from fields: CalendarEventFields, tag: Tag) -> Event? {
    guard fields.state != .canceled else { return nil }

    return Event(
        id: identity(of: fields),
        calendar: fields.calendarIdentifier,
        tag: tag,
        title: fields.title.isEmpty ? busyTitle : fields.title,
        start: fields.start,
        end: fields.end,
        isAllDay: fields.isAllDay,
        status: status(of: fields),
        link: safeLink(fields.link)
    )
}

/// Which event this is, across every calendar it appears on. One instance of a
/// repeating event is its own event, so the occurrence is part of the identity.
func identity(of fields: CalendarEventFields) -> String {
    // An event with no UID can still be told apart by when it starts.
    let uid = fields.uid.isEmpty ? fields.calendarIdentifier : fields.uid
    let instance = fields.occurrence ?? fields.start
    return "\(uid)@\(instance.timeIntervalSince1970)"
}

/// Declined if you said no. Tentative if you were unsure, or the calendar is.
/// Anything else counts as accepted, which is what a plain busy block is.
func status(of fields: CalendarEventFields) -> Status {
    if fields.response == .declined { return .declined }
    if fields.response == .tentative || fields.state == .tentative { return .tentative }
    return .accepted
}

/// The events to show for a set of calendars, with each calendar's tag applied.
/// A calendar that is off contributes nothing.
public func events(
    from fields: [CalendarEventFields],
    tags: (String) -> CalendarSetting
) -> [Event] {
    fields.compactMap { one in
        guard let tag = tags(one.calendarIdentifier).tag else { return nil }
        return event(from: one, tag: tag)
    }
}
