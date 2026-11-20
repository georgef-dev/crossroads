// Which events overlap, and how each one is shown. Spec: specs/ConflictFlags.tla.

import Foundation

/// Whether a calendar is personal or work. A calendar that is off has no tag,
/// so its events never reach here.
public enum Tag: String, Codable, Sendable, CaseIterable {
    case personal
    case work
}

public enum Status: String, Codable, Sendable, CaseIterable {
    case accepted
    case tentative
    case declined
    case cancelled

    /// Declined and cancelled events are never flagged; tentative ones can be.
    public var isActive: Bool {
        self == .accepted || self == .tentative
    }
}

/// The kind of overlap an event shows.
public enum Kind: String, Codable, Sendable, CaseIterable {
    case none
    case same
    case mixed
}

/// One event as it appears on one calendar.
public struct Event: Hashable, Sendable {
    /// Copies of one event on different calendars share an id.
    public let id: String
    public let calendar: String
    public let tag: Tag
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let status: Status
    /// Where the event opens, empty when it has no link.
    public let link: String

    public init(
        id: String,
        calendar: String,
        tag: Tag,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        status: Status,
        link: String = ""
    ) {
        self.id = id
        self.calendar = calendar
        self.tag = tag
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.status = status
        self.link = link
    }
}

/// One card for a colliding pair of events.
public struct Overlap: Hashable, Sendable {
    public let first: Event
    public let second: Event
    /// When both events are happening.
    public let start: Date
    public let end: Date
}

/// One overlap per pair of colliding events, even when an event sits on two calendars.
public func overlaps(_ events: [Event]) -> [Overlap] {
    var seen: Set<Pair> = []
    var result: [Overlap] = []
    for (index, first) in events.enumerated() {
        for second in events[(index + 1)...] {
            let pair = Pair(first.id, second.id)
            guard conflict(first, second), !seen.contains(pair) else { continue }
            seen.insert(pair)
            result.append(
                Overlap(
                    first: first,
                    second: second,
                    start: max(first.start, second.start),
                    end: min(first.end, second.end)
                )
            )
        }
    }
    return result
}

/// The kind of each event, in the same order as the input. A reminder due
/// during an event flags it just as another event would.
public func classify(_ events: [Event], reminders: [Reminder] = []) -> [Kind] {
    events.map { kind(of: $0, among: events, reminders: reminders) }
}

private func kind(of event: Event, among events: [Event], reminders: [Reminder]) -> Kind {
    let partnerTags = events.filter { conflict(event, $0) }.map(\.tag)
        + reminders.filter { clash($0, event) }.map(\.tag)
    if partnerTags.contains(where: { $0 != event.tag }) { return .mixed }
    return partnerTags.isEmpty ? .none : .same
}

private func conflict(_ a: Event, _ b: Event) -> Bool {
    canConflict(a)
        && canConflict(b)
        && a.id != b.id
        && a.start < b.end
        && b.start < a.end
}

private func canConflict(_ event: Event) -> Bool {
    !event.isAllDay && event.status.isActive
}

/// Two event ids, in either order. Copies of one event share its id, so a
/// collision between two events is one pair however many calendars they sit on.
private struct Pair: Hashable {
    let lower: String
    let higher: String

    init(_ one: String, _ other: String) {
        (lower, higher) = one <= other ? (one, other) : (other, one)
    }
}
