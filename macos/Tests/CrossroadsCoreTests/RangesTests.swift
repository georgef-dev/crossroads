// Ported from omarchy/plugin/tests/Model.test.js.
//
// The parseSnapshot cases are not ported: that function reads untrusted
// output from `crossroads fetch`, and the Mac has no such command. The bounds
// it enforced live on Snapshot instead, and are tested here.

import Foundation
import Testing

import CrossroadsCore

@Suite("Ranges and grouping")
struct RangesTests {
    let events = [
        event("overnight", day: 16, hour: 22, hours: 4),
        event("today", day: 17, hour: 9),
        event("tomorrow", day: 18, hour: 9),
        event("in-three", day: 20, hour: 9),
        event("in-seven", day: 24, hour: 9),
        event("in-eight", day: 25, hour: 9),
        event("in-fourteen", day: 31, hour: 9),
    ]

    func inRange(_ days: Int) -> [String] {
        ids(eventsInRange(events, now: now, days: days, calendar: newYork))
    }

    @Test("range today shows only today, including events still running from yesterday")
    func rangeToday() {
        #expect(inRange(0) == ["overnight", "today"])
    }

    @Test("range today + N includes the Nth day and stops after it")
    func rangeDays() {
        #expect(inRange(1) == ["overnight", "today", "tomorrow"])
        #expect(inRange(3) == ["overnight", "today", "tomorrow", "in-three"])
        #expect(inRange(7).last == "in-seven")
        #expect(inRange(14).last == "in-fourteen")
    }

    @Test("ranges are today, +1, +3, +7, +14, defaulting to +7")
    func rangeOptions() {
        #expect(ranges == [0, 1, 3, 7, 14])
        #expect(defaultRange == 7)
        #expect(nextRange(from: 7, step: 1) == 14)
        #expect(nextRange(from: 14, step: 1) == 14)
        #expect(nextRange(from: 0, step: -1) == 0)
        #expect(nextRange(from: 3, step: -1) == 1)
    }

    @Test("Tab wraps around the ranges")
    func rangeWraps() {
        var visited = [0]
        for _ in 0..<5 {
            visited.append(nextRange(from: visited.last!, step: 1, wrap: true))
        }
        #expect(visited == [0, 1, 3, 7, 14, 0])
        #expect(nextRange(from: 0, step: -1, wrap: true) == 14)
    }

    @Test("an unknown range starts from the default")
    func unknownRange() {
        #expect(nextRange(from: 5, step: 1) == 14)
    }

    @Test("all-day events cover their local day")
    func allDayEvents() {
        let birthday = FlaggedEvent(
            event: Event(
                id: "bday",
                calendar: "Family",
                tag: .personal,
                title: "bday",
                start: newYork.startOfDay(for: moment(day: 18, hour: 12)),
                end: newYork.startOfDay(for: moment(day: 19, hour: 12)),
                isAllDay: true,
                status: .accepted
            ),
            kind: .none,
            calendarName: "Family"
        )
        #expect(ids(eventsInRange([birthday], now: now, days: 0, calendar: newYork)) == [])
        #expect(ids(eventsInRange([birthday], now: now, days: 1, calendar: newYork)) == ["bday"])
    }

    @Test("events group by start day, earlier starts under today")
    func grouping() {
        let days = groupByDay(
            eventsInRange(events, now: now, days: 1, calendar: newYork),
            now: now,
            calendar: newYork
        )
        #expect(days.map { newYork.component(.day, from: $0.day) } == [17, 18])
        #expect(days.map { ids($0.events) } == [["overnight", "today"], ["tomorrow"]])
    }

    @Test("the bar counts flagged events")
    func counting() {
        let flagged = [
            event("a", day: 17, hour: 9, kind: .mixed),
            event("b", day: 17, hour: 9, kind: .same),
            event("c", day: 17, hour: 12),
        ]
        #expect(flaggedCount(flagged) == 2)
    }

    @Test("color follows the kind")
    func shades() {
        #expect(shade(.none) == .plain)
        #expect(shade(.same) == .darker)
        #expect(shade(.mixed) == .blend)
    }

    @Test("a snapshot is bounded, however much an account holds")
    func snapshotIsBounded() {
        let many = (0..<600).map { event("e\($0)", day: 17, hour: 9) }
        let mail = (0..<80).map {
            MailMessage(id: "m\($0)", subject: "s", sender: "s", account: "a", link: "")
        }
        let snapshot = Snapshot(events: many, mail: mail, errors: mail.map(\.id))

        #expect(snapshot.events.count == maxEvents)
        #expect(snapshot.mail.count == maxMail)
        #expect(snapshot.errors.count == maxMail)
    }
}
