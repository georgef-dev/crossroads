// A made-up day, so the panel can be built and driven before EventKit and
// Gmail are wired up in steps 5 and 6. Nothing here reaches a real account.

import Foundation

import CrossroadsCore

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
        event("standup", "Team standup", on: today, from: 9, to: 9.25, calendarID: "work", tag: .work),
        event("review", "Design review", on: today, from: 13, to: 14, calendarID: "work", tag: .work),
        // These two collide: the panel should show one personal + work card.
        event("pickup", "Kids pickup", on: today, from: 15, to: 15.5, calendarID: "family", tag: .personal),
        event("busy", "Busy", on: today, from: 15.25, to: 16, calendarID: "work", tag: .work),
        // So do these two, within one tag.
        event("dentist", "Dentist", on: today, from: 17, to: 18, calendarID: "family", tag: .personal),
        event("gym", "Gym", on: today, from: 17.5, to: 18.5, calendarID: "family", tag: .personal),
        event("birthday", "Alex's birthday", on: today, from: 0, to: 24, calendarID: "family", tag: .personal, isAllDay: true),
        event("school", "School run", on: tomorrow, from: 8, to: 8.5, calendarID: "family", tag: .personal),
        event("declined", "Optional sync", on: today, from: 15.5, to: 16, calendarID: "work", tag: .work, status: .declined),
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
            subject: "Invoice attached",
            sender: "Accounts",
            account: "you@example.com",
            received: now.addingTimeInterval(-7200),
            link: "https://mail.google.com/mail/u/0/#inbox"
        ),
        MailMessage(
            id: "m3",
            subject: "Re: holiday plans",
            sender: "Sam",
            account: "you@example.com",
            received: now.addingTimeInterval(-86400),
            link: "https://mail.google.com/mail/u/0/#inbox"
        ),
    ]

    return buildSnapshot(
        fetchedAt: now,
        events: events,
        calendarNames: ["work": "Work", "family": "Family"],
        mail: mail
    )
}

let sampleCalendars = [
    CalendarInfo(id: "family", name: "Family", source: "iCloud"),
    CalendarInfo(id: "work", name: "Work", source: "Google"),
    CalendarInfo(id: "holidays", name: "Holidays", source: "Google"),
]
