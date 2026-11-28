// Reminders: the attention list, and clashing with events.
// The invariants are in specs/ConflictFlags.tla.

import Foundation
import Testing

import CrossroadsCore

@Suite("Reminders")
struct RemindersTests {
    func reminder(
        _ id: String,
        tag: CrossroadsCore.Tag = .personal,
        due: Date? = moment(day: 17, hour: 15),
        hasTime: Bool = true,
        isCompleted: Bool = false
    ) -> Reminder {
        Reminder(
            id: id,
            list: tag == .work ? "work-list" : "home-list",
            tag: tag,
            title: id,
            due: due,
            hasTime: hasTime,
            isCompleted: isCompleted
        )
    }

    /// A meeting from 15:00 to 16:00 on the work calendar.
    let meeting = Event(
        id: "meeting",
        calendar: "work",
        tag: .work,
        title: "Meeting",
        start: moment(day: 17, hour: 15),
        end: moment(day: 17, hour: 16),
        isAllDay: false,
        status: .accepted
    )

    @Test("a reminder due during an event clashes with it")
    func duringAnEvent() {
        #expect(clash(reminder("call", due: moment(day: 17, hour: 15, minute: 30)), meeting))
    }

    @Test("the event's start counts and its end does not")
    func halfOpenWindow() {
        // Due exactly when the meeting starts: that is during it.
        #expect(clash(reminder("at-start", due: moment(day: 17, hour: 15)), meeting))
        // Due exactly when it ends: the meeting is over.
        #expect(!clash(reminder("at-end", due: moment(day: 17, hour: 16)), meeting))
        #expect(!clash(reminder("before", due: moment(day: 17, hour: 14, minute: 59)), meeting))
    }

    @Test("a completed reminder, or one with no time of day, never clashes")
    func cannotClash() {
        #expect(!clash(reminder("done", isCompleted: true), meeting))
        #expect(!clash(reminder("dateOnly", hasTime: false), meeting))
        #expect(!clash(reminder("someday", due: nil), meeting))
    }

    @Test("a reminder never clashes with an all-day or declined event")
    func eventMustBeFlaggable() {
        func variant(isAllDay: Bool = false, status: Status = .accepted) -> Event {
            Event(
                id: "e", calendar: "work", tag: .work, title: "e",
                start: meeting.start, end: meeting.end,
                isAllDay: isAllDay, status: status
            )
        }
        #expect(!clash(reminder("r"), variant(isAllDay: true)))
        #expect(!clash(reminder("r"), variant(status: .declined)))
        #expect(!clash(reminder("r"), variant(status: .cancelled)))
        // Unsure still counts.
        #expect(clash(reminder("r"), variant(status: .tentative)))
    }

    @Test("a clash flags both the reminder and the event")
    func bothAreFlagged() {
        let clashing = reminder("call", tag: .personal, due: moment(day: 17, hour: 15, minute: 30))

        #expect(classifyReminders([clashing], events: [meeting]) == [.mixed])
        #expect(classify([meeting], reminders: [clashing]) == [.mixed])
    }

    @Test("a clash within one tag shows as same, not personal + work")
    func sameTagClash() {
        let work = reminder("prep", tag: .work, due: moment(day: 17, hour: 15, minute: 30))

        #expect(classifyReminders([work], events: [meeting]) == [.same])
        #expect(classify([meeting], reminders: [work]) == [.same])
    }

    @Test("a reminder that clashes with nothing is not flagged, and nor is the event")
    func noClash() {
        let elsewhere = reminder("later", due: moment(day: 17, hour: 20))

        #expect(classifyReminders([elsewhere], events: [meeting]) == [.none])
        #expect(classify([meeting], reminders: [elsewhere]) == [.none])
    }

    @Test("reminders never clash with each other")
    func remindersIgnoreEachOther() {
        let first = reminder("a", due: moment(day: 17, hour: 15))
        let second = reminder("b", tag: .work, due: moment(day: 17, hour: 15))

        #expect(classifyReminders([first, second], events: []) == [.none, .none])
    }

    @Test("no reminders means classify behaves exactly as before")
    func classifyUnchanged() {
        #expect(classify([meeting]) == classify([meeting], reminders: []))
        #expect(classify([meeting]) == [.none])
    }

    @Test("the attention list is everything overdue plus everything due today")
    func attentionList() {
        let now = moment(day: 17, hour: 12)
        let all = [
            reminder("overdue-days", due: moment(day: 14, hour: 9)),
            reminder("overdue-today", due: moment(day: 17, hour: 9)),
            reminder("later-today", due: moment(day: 17, hour: 22)),
            reminder("tomorrow", due: moment(day: 18, hour: 9)),
            reminder("no-due-date", due: nil),
            reminder("done", due: moment(day: 14, hour: 9), isCompleted: true),
        ]

        let needing = remindersNeedingAttention(all, now: now, calendar: newYork)

        // Soonest first, and nothing from tomorrow onwards.
        #expect(needing.map(\.id) == ["overdue-days", "overdue-today", "later-today"])
    }

    @Test("a reminder due today with no time of day still needs attention")
    func dateOnlyStillCounts() {
        let dateOnly = reminder(
            "shopping",
            due: newYork.startOfDay(for: moment(day: 17, hour: 12)),
            hasTime: false
        )
        let needing = remindersNeedingAttention([dateOnly], now: moment(day: 17, hour: 12), calendar: newYork)
        #expect(needing.map(\.id) == ["shopping"])
    }
}
