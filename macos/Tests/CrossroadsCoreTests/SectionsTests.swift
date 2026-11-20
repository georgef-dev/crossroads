// Ported from omarchy/plugin/tests/Modal.test.js.

import Foundation
import Testing

import CrossroadsCore

@Suite("Panel sections")
struct SectionsTests {
    let snapshot = Snapshot(
        events: [
            event("pickup", day: 17, hour: 15),
            event("dentist", day: 18, hour: 10, calendarName: "Partner"),
            event("trip", day: 30, hour: 9),
        ],
        overlaps: [card(day: 17, hour: 15), card(day: 20, hour: 9), card(day: 30, hour: 9)],
        mail: [
            MailMessage(
                id: "m1",
                subject: "Early pickup Friday",
                sender: "School office",
                account: "you@example.com",
                link: "https://mail.google.com/mail/?authuser=gf#all/t1"
            )
        ]
    )

    func sections(_ query: String = "", days: Int = 7, snapshot: Snapshot? = nil) -> [Section] {
        panelSections(
            snapshot ?? self.snapshot,
            now: now,
            days: days,
            query: query,
            calendar: newYork
        )
    }

    func eventIDs(_ section: Section) -> [String] {
        section.items.compactMap {
            if case .event(let flagged) = $0.value { return flagged.event.id }
            return nil
        }
    }

    @Test("without a query: overlaps in range, then today, then mail")
    func defaultOrder() {
        let built = sections()
        #expect(built.map(\.key) == [.overlaps, .today, .mail])
        #expect(built[0].items.count == 2)
        #expect(eventIDs(built[1]) == ["pickup"])
    }

    @Test("the overlaps section is hidden when there are none in range")
    func overlapsHidden() {
        let without = Snapshot(events: snapshot.events, overlaps: [], mail: snapshot.mail)
        #expect(sections(snapshot: without).map(\.key) == [.today, .mail])
    }

    @Test("today and mail stay visible when empty, so the view keeps its shape")
    func emptyKeepsShape() {
        #expect(sections(snapshot: Snapshot()).map(\.key) == [.today, .mail])
    }

    @Test("a query searches every fetched event and all mail")
    func searching() {
        let built = sections("PICKUP", days: 0)
        #expect(built.map(\.key) == [.events, .mail])
        #expect(eventIDs(built[0]) == ["pickup"])
        if case .mail(let message) = built[1].items[0].value {
            #expect(message.subject == "Early pickup Friday")
        } else {
            Issue.record("the second section should be mail")
        }
    }

    @Test("a query matches calendar names and senders, and drops empty sections")
    func searchingElsewhere() {
        #expect(eventIDs(sections("partner")[0]) == ["dentist"])
        #expect(sections("school").map(\.key) == [.mail])
        #expect(sections("nothing like this").isEmpty)
    }

    @Test("mail is a two-column grid, everything else a list")
    func columns() {
        let built = panelSections(
            Snapshot(mail: [
                MailMessage(id: "a", subject: "a", sender: "a", account: "a", link: ""),
                MailMessage(id: "b", subject: "b", sender: "b", account: "b", link: ""),
            ]),
            now: now,
            days: 7,
            calendar: newYork
        )
        #expect(built.map { [$0.key.rawValue, String($0.columns)] } == [["today", "1"], ["mail", "2"]])
    }

    @Test("items are numbered across sections for keyboard selection")
    func numbering() {
        let built = sections()
        #expect(itemCount(built) == 4)
        #expect(built.flatMap { $0.items.map(\.index) } == [0, 1, 2, 3])
        if case .mail = itemAt(built, index: 3)?.value {} else {
            Issue.record("item 3 should be mail")
        }
        #expect(itemAt(built, index: 9) == nil)
    }

    @Test("enter opens the item's link; a card opens its first event")
    func opening() {
        let built = sections()
        #expect(linkOf(itemAt(built, index: 0)) == "https://www.icloud.com/calendar/")
        #expect(linkOf(itemAt(built, index: 3)) == "https://mail.google.com/mail/?authuser=gf#all/t1")
        #expect(linkOf(nil) == "")
    }

    @Test("only links to the services Crossroads reads can open")
    func links() {
        let allowed = [
            "https://www.google.com/calendar/event?eid=abc",
            "https://calendar.google.com/calendar/r/day/2026/11/17?authuser=gf%40x.com",
            "https://mail.google.com/mail/?authuser=gf#all/t1",
            "https://www.icloud.com/calendar/",
        ]
        for link in allowed {
            #expect(safeLink(link) == link)
        }

        let refused = [
            "http://mail.google.com/",
            "https://mail.google.com.evil.com/",
            "https://evil.com/?https://mail.google.com/",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "https://www.google.com/search?q=x",
            "https://mail.google.com/ --flag",
            "https://mail.google.com/\nx",
            "",
        ]
        for link in refused {
            #expect(safeLink(link) == "", "\(link)")
        }
    }

    @Test("timeline spans are fractions of the window, clamped to it")
    func spans() {
        let start = moment(day: 17, hour: 6)
        let end = moment(day: 17, hour: 22)

        #expect(
            timelineSpan(
                start: moment(day: 17, hour: 14),
                end: moment(day: 17, hour: 18),
                windowStart: start,
                windowEnd: end
            ) == Span(x: 0.5, width: 0.25)
        )
        #expect(
            timelineSpan(
                start: moment(day: 17, hour: 4),
                end: moment(day: 17, hour: 7),
                windowStart: start,
                windowEnd: end
            ) == Span(x: 0, width: 1.0 / 16.0)
        )
        #expect(
            timelineSpan(start: start, end: end, windowStart: end, windowEnd: start)
                == Span(x: 0, width: 0)
        )
    }

    @Test("the day strip covers 6 to 22, widened for earlier or later events")
    func dayStrip() {
        func hours(_ window: Window) -> [Int] {
            let last = newYork.component(.hour, from: window.end)
            return [newYork.component(.hour, from: window.start), last == 0 ? 24 : last]
        }

        #expect(hours(dayWindow([event("x", day: 17, hour: 9)], now: now, calendar: newYork)) == [6, 22])

        let wide = [
            event("early", day: 17, hour: 5),
            event("late", day: 17, hour: 22, end: moment(day: 17, hour: 23, minute: 30)),
        ]
        #expect(hours(dayWindow(wide, now: now, calendar: newYork)) == [5, 24])

        let allDay = [event("bday", day: 17, hour: 0, hours: 24, isAllDay: true)]
        #expect(hours(dayWindow(allDay, now: now, calendar: newYork)) == [6, 22])
    }

    @Test("a card's timeline spans both of its events")
    func cardTimeline() {
        let window = cardWindow(card(day: 17, hour: 15))
        #expect(newYork.component(.hour, from: window.start) == 14)
        #expect(newYork.component(.hour, from: window.end) == 17)
    }
}
