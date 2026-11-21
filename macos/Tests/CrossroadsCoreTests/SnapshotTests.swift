// Building a snapshot from what a fetch found.
// Ported from omarchy/src/crossroads/snapshot.py.

import Foundation
import Testing

import CrossroadsCore

@Suite("Building a snapshot")
struct SnapshotTests {
    func timed(_ id: String, calendar: String, tag: CrossroadsCore.Tag, hour: Int, minutes: Int) -> Event {
        Event(
            id: id,
            calendar: calendar,
            tag: tag,
            title: id,
            start: moment(day: 17, hour: hour),
            end: moment(day: 17, hour: hour).addingTimeInterval(TimeInterval(minutes) * 60),
            isAllDay: false,
            status: .accepted
        )
    }

    @Test("every event carries the kind the rules give it, and its calendar's name")
    func kindsAndNames() {
        let events = [
            timed("busy", calendar: "work", tag: .work, hour: 15, minutes: 45),
            timed("pickup", calendar: "family", tag: .personal, hour: 15, minutes: 30),
        ]

        let snapshot = buildSnapshot(
            events: events,
            calendarNames: ["family": "Family", "work": "Work"]
        )

        // Sorted by start, so the two 15:00 events keep the order they came in.
        #expect(snapshot.events.map(\.event.id) == ["busy", "pickup"])
        #expect(snapshot.events.allSatisfy { $0.kind == .mixed })
        #expect(snapshot.events.map(\.calendarName) == ["Work", "Family"])
    }

    @Test("a calendar with no name shows its identifier")
    func unnamedCalendar() {
        let snapshot = buildSnapshot(events: [timed("x", calendar: "abc123", tag: .personal, hour: 9, minutes: 30)])
        #expect(snapshot.events.first?.calendarName == "abc123")
    }

    @Test("a card is personal + work when its two events disagree, and same when they agree")
    func cardKinds() {
        let crossing = buildSnapshot(events: [
            timed("pickup", calendar: "family", tag: .personal, hour: 15, minutes: 30),
            timed("busy", calendar: "work", tag: .work, hour: 15, minutes: 45),
        ])
        #expect(crossing.overlaps.map(\.kind) == [.mixed])
        #expect(crossing.overlaps.first?.events.allSatisfy { $0.kind == .mixed } == true)

        let agreeing = buildSnapshot(events: [
            timed("dentist", calendar: "family", tag: .personal, hour: 10, minutes: 60),
            timed("gym", calendar: "family", tag: .personal, hour: 10, minutes: 90),
        ])
        #expect(agreeing.overlaps.map(\.kind) == [.same])
    }

    @Test("cards cover the time both events are happening")
    func cardWindows() {
        let snapshot = buildSnapshot(events: [
            timed("pickup", calendar: "family", tag: .personal, hour: 15, minutes: 30),
            timed("busy", calendar: "work", tag: .work, hour: 15, minutes: 45),
        ])
        let card = snapshot.overlaps.first
        #expect(card?.start == moment(day: 17, hour: 15))
        #expect(card?.end == moment(day: 17, hour: 15, minute: 30))
    }

    @Test("events and cards come out in time order")
    func timeOrder() {
        let snapshot = buildSnapshot(events: [
            timed("late", calendar: "family", tag: .personal, hour: 16, minutes: 60),
            timed("early", calendar: "family", tag: .personal, hour: 9, minutes: 60),
            timed("clash", calendar: "work", tag: .work, hour: 16, minutes: 30),
        ])
        #expect(snapshot.events.map(\.event.id) == ["early", "late", "clash"])
        #expect(snapshot.overlaps.count == 1)
    }

    @Test("mail comes out newest first")
    func mailOrder() {
        func message(_ id: String, hour: Int) -> MailMessage {
            MailMessage(
                id: id,
                subject: id,
                sender: "s",
                account: "a",
                received: moment(day: 17, hour: hour),
                link: ""
            )
        }
        let snapshot = buildSnapshot(
            events: [],
            mail: [message("older", hour: 8), message("newest", hour: 17), message("middle", hour: 12)]
        )
        #expect(snapshot.mail.map(\.id) == ["newest", "middle", "older"])
    }

    @Test("no overlap means no cards")
    func noCards() {
        let snapshot = buildSnapshot(events: [
            timed("a", calendar: "family", tag: .personal, hour: 9, minutes: 60),
            timed("b", calendar: "work", tag: .work, hour: 14, minutes: 60),
        ])
        #expect(snapshot.overlaps.isEmpty)
        #expect(snapshot.events.allSatisfy { $0.kind == .none })
    }
}
