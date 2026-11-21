// Ranges, grouping by day, and timeline windows.
// Ported from omarchy/plugin/Model.js.
//
// Day boundaries are local, as they are in the plugin. The calendar is a
// parameter so tests can pin a time zone, the way the node tests pin TZ.

import Foundation

/// How many days past today the view can show.
public let ranges = [0, 1, 3, 7, 14]
public let defaultRange = 7

/// How an event is colored: its tag's color, a darker shade of it when it
/// overlaps its own tag, or a blend of both tags when personal meets work.
/// The colors themselves belong to the UI; this is only the choice between them.
public enum Shade: String, Sendable {
    case plain
    case darker
    case blend
}

public func shade(_ kind: Kind) -> Shade {
    switch kind {
    case .mixed: .blend
    case .same: .darker
    case .none: .plain
    }
}

/// Arrows in the panel stop at the ends; Tab in the modal wraps around.
public func nextRange(from days: Int, step: Int, wrap: Bool = false) -> Int {
    let index = ranges.firstIndex(of: days) ?? ranges.firstIndex(of: defaultRange)!
    if wrap {
        let count = ranges.count
        return ranges[((index + step) % count + count) % count]
    }
    return ranges[min(max(index + step, 0), ranges.count - 1)]
}

/// Today plus `days` more days, in local time.
public func eventsInRange(
    _ events: [FlaggedEvent],
    now: Date,
    days: Int,
    calendar: Calendar = .current
) -> [FlaggedEvent] {
    let from = calendar.startOfDay(for: now)
    let until = addingDays(days + 1, to: from, calendar: calendar)
    return events.filter { $0.event.start < until && $0.event.end > from }
}

/// The cards that fall in the range, by the same rule as events.
public func cardsInRange(
    _ cards: [OverlapCard],
    now: Date,
    days: Int,
    calendar: Calendar = .current
) -> [OverlapCard] {
    let from = calendar.startOfDay(for: now)
    let until = addingDays(days + 1, to: from, calendar: calendar)
    return cards.filter { $0.start < until && $0.end > from }
}

/// One day's worth of events, under the day they start.
public struct Day: Hashable, Sendable {
    public let day: Date
    public let events: [FlaggedEvent]

    public init(day: Date, events: [FlaggedEvent]) {
        self.day = day
        self.events = events
    }
}

/// Events grouped under the day they start, or today if they started earlier.
public func groupByDay(
    _ events: [FlaggedEvent],
    now: Date,
    calendar: Calendar = .current
) -> [Day] {
    let today = calendar.startOfDay(for: now)
    var days: [Day] = []
    for event in events {
        var day = calendar.startOfDay(for: event.event.start)
        if day < today { day = today }
        if let last = days.last, last.day == day {
            days[days.count - 1] = Day(day: day, events: last.events + [event])
        } else {
            days.append(Day(day: day, events: [event]))
        }
    }
    return days
}

public func flaggedCount(_ events: [FlaggedEvent]) -> Int {
    events.filter { $0.kind != .none }.count
}

/// Position of [start, end) along a timeline window, as fractions of its width.
public struct Span: Hashable, Sendable {
    public let x: Double
    public let width: Double

    public init(x: Double, width: Double) {
        self.x = x
        self.width = width
    }
}

public func timelineSpan(start: Date, end: Date, windowStart: Date, windowEnd: Date) -> Span {
    let length = windowEnd.timeIntervalSince(windowStart)
    guard length > 0 else { return Span(x: 0, width: 0) }
    let from = min(max(start.timeIntervalSince(windowStart) / length, 0), 1)
    let to = min(max(end.timeIntervalSince(windowStart) / length, 0), 1)
    return Span(x: from, width: max(0, to - from))
}

/// A window of time a timeline covers.
public struct Window: Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// The day strip covers 6:00 to 22:00, widened to whole hours that fit
/// earlier or later timed events.
public func dayWindow(
    _ events: [FlaggedEvent],
    now: Date,
    calendar: Calendar = .current
) -> Window {
    let day = calendar.startOfDay(for: now)
    let nextDay = addingDays(1, to: day, calendar: calendar)
    var first = 6
    var last = 22

    for flagged in events where !flagged.event.isAllDay {
        let start = flagged.event.start
        let end = flagged.event.end
        if start >= day {
            first = min(first, calendar.component(.hour, from: start))
        }
        if end <= nextDay {
            let minute = calendar.component(.minute, from: end)
            last = max(last, calendar.component(.hour, from: end) + (minute > 0 ? 1 : 0))
        } else {
            last = 24
        }
        if start < day { first = 0 }
    }

    return Window(
        start: day.addingTimeInterval(TimeInterval(first) * 3600),
        end: day.addingTimeInterval(TimeInterval(last) * 3600)
    )
}

/// A card's timeline spans both events, with the overlap inside it.
public func cardWindow(_ card: OverlapCard) -> Window {
    Window(
        start: card.events.map(\.event.start).min() ?? card.start,
        end: card.events.map(\.event.end).max() ?? card.end
    )
}

/// `days` whole days after `date`, keeping to local day boundaries.
private func addingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
    calendar.date(byAdding: .day, value: days, to: date) ?? date
}
