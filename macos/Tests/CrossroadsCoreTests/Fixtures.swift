// Shared fixtures for the view-logic tests.
//
// The node tests run with TZ=America/New_York so day boundaries are fixed
// everywhere. Swift takes the calendar as a parameter instead, so the tests
// pin the same zone without touching the environment.

import Foundation

import CrossroadsCore

let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// A local wall-clock time in November 2026, the month the node tests use.
func moment(day: Int, hour: Int, minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// 2026-11-17 07:30 local, "now" in every ported test.
let now = moment(day: 17, hour: 7, minute: 30)

func event(
    _ id: String,
    day: Int,
    hour: Int,
    hours: Int = 1,
    kind: Kind = .none,
    tag: Tag = .personal,
    isAllDay: Bool = false,
    calendarName: String = "Family",
    link: String = "https://www.icloud.com/calendar/",
    end: Date? = nil
) -> FlaggedEvent {
    FlaggedEvent(
        event: Event(
            id: id,
            calendar: calendarName,
            tag: tag,
            title: id,
            start: moment(day: day, hour: hour),
            end: end ?? moment(day: day, hour: hour + hours),
            isAllDay: isAllDay,
            status: .accepted,
            link: link
        ),
        kind: kind,
        calendarName: calendarName
    )
}

/// A card shaped like the node fixture: two events that overlap for an hour.
func card(day: Int, hour: Int) -> OverlapCard {
    OverlapCard(
        events: [event("a", day: day, hour: hour - 1, hours: 2), event("b", day: day, hour: hour, hours: 2)],
        start: moment(day: day, hour: hour),
        end: moment(day: day, hour: hour + 1),
        kind: .same
    )
}

func ids(_ events: [FlaggedEvent]) -> [String] {
    events.map(\.event.id)
}
