// Where the reminders that need attention show up in the panel.

import Foundation
import Testing

import CrossroadsCore

@Suite("Reminders in the panel")
struct ReminderSectionsTests {
    func reminder(_ id: String, hour: Int, title: String? = nil) -> Reminder {
        Reminder(
            id: id,
            list: "home-list",
            tag: .personal,
            title: title ?? id,
            due: moment(day: 17, hour: hour),
            hasTime: true,
            link: ""
        )
    }

    func snapshot(reminders: [Reminder], events: [Event] = []) -> Snapshot {
        buildSnapshot(
            events: events,
            reminders: reminders,
            now: now,
            calendar: newYork,
            mail: [MailMessage(id: "m", subject: "Hello", sender: "Sam", account: "a", link: "")]
        )
    }

    func keys(_ query: String = "", _ snapshot: Snapshot) -> [SectionKey] {
        panelSections(snapshot, now: now, days: 7, query: query, calendar: newYork).map(\.key)
    }

    @Test("reminders sit between the overlap cards and today")
    func order() {
        let built = keys("", snapshot(reminders: [reminder("call", hour: 9)]))
        #expect(built == [.reminders, .today, .mail])
    }

    @Test("the reminders section is hidden when none need attention")
    func hiddenWhenEmpty() {
        // Due tomorrow, so it needs no attention today.
        let tomorrow = Reminder(
            id: "later", list: "home-list", tag: .personal, title: "later",
            due: moment(day: 18, hour: 9), hasTime: true
        )
        #expect(keys("", snapshot(reminders: [tomorrow])) == [.today, .mail])
        #expect(keys("", snapshot(reminders: [])) == [.today, .mail])
    }

    @Test("only the reminders that need attention reach the view")
    func onlyAttention() {
        let built = snapshot(reminders: [
            reminder("overdue", hour: 9),
            Reminder(id: "next-week", list: "home-list", tag: .personal, title: "next week",
                     due: moment(day: 24, hour: 9), hasTime: true),
        ])
        #expect(built.reminders.map(\.reminder.id) == ["overdue"])
    }

    @Test("a reminder still flags an event even when it is not shown itself")
    func flagsWithoutBeingShown() {
        // Due next week, so it is not in the attention list, but it still
        // clashes with its event and must flag it.
        let future = Reminder(
            id: "next-week", list: "work-list", tag: .work, title: "next week",
            due: moment(day: 24, hour: 15, minute: 30), hasTime: true
        )
        let meeting = Event(
            id: "meeting", calendar: "family", tag: .personal, title: "Meeting",
            start: moment(day: 24, hour: 15), end: moment(day: 24, hour: 16),
            isAllDay: false, status: .accepted
        )

        let built = snapshot(reminders: [future], events: [meeting])

        #expect(built.reminders.isEmpty)
        #expect(built.events.map(\.kind) == [.mixed])
    }

    @Test("a query searches reminders by title and list")
    func searching() {
        let built = snapshot(reminders: [reminder("r1", hour: 9, title: "Call the school")])

        #expect(keys("school", built) == [.reminders])
        #expect(keys("home-list", built) == [.reminders])
        #expect(keys("nothing like this", built) == [])
    }

    @Test("reminders are numbered with everything else for keyboard selection")
    func numbering() {
        let built = panelSections(
            snapshot(reminders: [reminder("a", hour: 9), reminder("b", hour: 10)]),
            now: now, days: 7, calendar: newYork
        )
        #expect(itemCount(built) == 3)
        #expect(built.flatMap { $0.items.map(\.index) } == [0, 1, 2])
        if case .reminder = itemAt(built, index: 0)?.value {} else {
            Issue.record("item 0 should be a reminder")
        }
    }
}
