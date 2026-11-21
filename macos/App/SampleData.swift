// A made-up day, for the screenshot in the README.
//
// Nothing here reaches a real account, which is the point: the picture in the
// README must never show anybody's calendar. Reminder due times are relative
// to now, so one is always overdue and one is always still to come, whenever
// the screenshot is taken.

import Foundation

import CrossroadsCore

/// The moment the made-up day is drawn at: this morning, so the day ahead is
/// still ahead and only the one reminder meant to be late is late.
func sampleNow(calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: .now).addingTimeInterval(9 * 3600 + 12 * 60)
}

func sampleSnapshot(now: Date = .now, calendar: Calendar = .current) -> Snapshot {
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

    func event(
        _ id: String,
        _ title: String,
        on day: Date,
        from: Double,
        to: Double,
        calendarID: String,
        tag: Tag,
        isAllDay: Bool = false,
        status: Status = .accepted
    ) -> Event {
        Event(
            id: id,
            calendar: calendarID,
            tag: tag,
            title: title,
            start: day.addingTimeInterval(from * 3600),
            end: day.addingTimeInterval(to * 3600),
            isAllDay: isAllDay,
            status: status,
            link: "https://calendar.google.com/calendar/r/day"
        )
    }

    let events = [
        event("birthday", "Alex's birthday", on: today, from: 0, to: 24, calendarID: "family", tag: .personal, isAllDay: true),
        // These two collide: the panel shows one personal + work card.
        event("pickup", "Kids pickup", on: today, from: 15, to: 15.5, calendarID: "family", tag: .personal),
        event("busy", "Busy", on: today, from: 15.25, to: 16, calendarID: "work", tag: .work),
        event("school", "School run", on: tomorrow, from: 8, to: 8.5, calendarID: "family", tag: .personal),
    ]

    let mail = [
        MailMessage(
            id: "m1",
            subject: "Early pickup Friday",
            sender: "School office",
            account: "you@example.com",
            received: now.addingTimeInterval(-1800),
            link: "https://mail.google.com/mail/u/0/#inbox"
        ),
        MailMessage(
            id: "m2",
            subject: "Re: holiday plans",
            sender: "Sam",
            account: "you@example.com",
            received: now.addingTimeInterval(-7200),
            link: "https://mail.google.com/mail/u/0/#inbox"
        ),
    ]

    let reminders = [
        Reminder(
            id: "r1", list: "home", tag: .personal, title: "Call the school back",
            due: today.addingTimeInterval(8 * 3600 + 30 * 60), hasTime: true
        ),
        // Due during the busy block, so it shows as personal + work.
        Reminder(
            id: "r2", list: "work", tag: .work, title: "Send the quarter numbers",
            due: today.addingTimeInterval(15.5 * 3600), hasTime: true
        ),
    ]

    return buildSnapshot(
        fetchedAt: now,
        events: events,
        reminders: reminders,
        now: now,
        calendar: calendar,
        calendarNames: ["work": "Work", "family": "Family"],
        mail: mail
    )
}

let sampleCalendars = [
    CalendarInfo(id: "family", name: "Family", source: "iCloud", kind: .events),
    CalendarInfo(id: "personal", name: "Personal", source: "iCloud", kind: .events),
    CalendarInfo(id: "holidays", name: "Holidays", source: "you@example.com", kind: .events),
    CalendarInfo(id: "work", name: "Work", source: "you@company.com", kind: .events),
    CalendarInfo(id: "home", name: "Home", source: "iCloud", kind: .reminders),
    CalendarInfo(id: "worktasks", name: "Work tasks", source: "iCloud", kind: .reminders),
]

/// Settings to match, so the screenshot shows Off, Personal and Work together.
let sampleSettings = Settings(
    refreshMinutes: 30,
    keys: "default",
    defaultRange: 7,
    shortcut: .standard,
    tags: [
        "family": .personal,
        "personal": .personal,
        "holidays": .off,
        "work": .work,
        "home": .personal,
        "worktasks": .work,
    ]
)
