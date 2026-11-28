// Mapping a system calendar event onto the event the rules work on.
// The Omarchy equivalents are in omarchy/tests/test_google.py.

import Foundation
import Testing

import CrossroadsCore

@Suite("Calendar mapping")
struct CalendarMappingTests {
    func fields(
        uid: String = "abc-123",
        occurrence: Date? = nil,
        calendar: String = "family",
        title: String = "Dentist",
        isAllDay: Bool = false,
        state: EventState = .confirmed,
        response: Response? = nil,
        link: String = ""
    ) -> CalendarEventFields {
        CalendarEventFields(
            uid: uid,
            occurrence: occurrence,
            calendarIdentifier: calendar,
            title: title,
            start: moment(day: 17, hour: 10),
            end: moment(day: 17, hour: 11),
            isAllDay: isAllDay,
            state: state,
            response: response,
            link: link
        )
    }

    @Test("an event keeps its title, times and calendar")
    func plainEvent() {
        let mapped = event(from: fields(), tag: .personal)
        #expect(mapped?.title == "Dentist")
        #expect(mapped?.calendar == "family")
        #expect(mapped?.tag == .personal)
        #expect(mapped?.start == moment(day: 17, hour: 10))
        #expect(mapped?.end == moment(day: 17, hour: 11))
        #expect(mapped?.status == .accepted)
    }

    @Test("a cancelled event is dropped, not carried with a status")
    func cancelledIsDropped() {
        #expect(event(from: fields(state: .canceled), tag: .personal) == nil)
    }

    @Test("your own answer decides the status, and the calendar's answer is the fallback")
    func statuses() {
        #expect(event(from: fields(response: .declined), tag: .work)?.status == .declined)
        #expect(event(from: fields(response: .tentative), tag: .work)?.status == .tentative)
        #expect(event(from: fields(state: .tentative), tag: .work)?.status == .tentative)
        // Unsure beats the calendar being sure.
        #expect(event(from: fields(state: .confirmed, response: .tentative), tag: .work)?.status == .tentative)
        // Nothing to answer, like a plain busy block, counts as accepted.
        #expect(event(from: fields(response: nil), tag: .work)?.status == .accepted)
        #expect(event(from: fields(response: .pending), tag: .work)?.status == .accepted)
    }

    @Test("a free/busy event with no title shows as Busy")
    func busyBlock() {
        #expect(event(from: fields(title: ""), tag: .work)?.title == busyTitle)
    }

    @Test("the same meeting on two calendars shares an id, so it cannot conflict with itself")
    func copiesShareIdentity() {
        let mine = event(from: fields(calendar: "family"), tag: .personal)!
        let partners = event(from: fields(calendar: "partner"), tag: .personal)!

        #expect(mine.id == partners.id)
        #expect(mine.calendar != partners.calendar)
        // The rules then see one event on two calendars, not two events.
        #expect(classify([mine, partners]) == [.none, .none])
        #expect(overlaps([mine, partners]).isEmpty)
    }

    @Test("two instances of a repeating event are different events")
    func repeatingInstances() {
        let first = event(from: fields(occurrence: moment(day: 17, hour: 10)), tag: .personal)!
        let second = event(from: fields(occurrence: moment(day: 18, hour: 10)), tag: .personal)!
        #expect(first.id != second.id)
    }

    @Test("an event with no UID is still told apart by when it starts")
    func missingUID() {
        let mapped = event(from: fields(uid: ""), tag: .personal)
        #expect(mapped?.id.hasPrefix("family@") == true)
    }

    @Test("only a link to a service Crossroads reads survives")
    func links() {
        let good = "https://calendar.google.com/calendar/r/day/2026/11/17"
        #expect(event(from: fields(link: good), tag: .personal)?.link == good)
        #expect(event(from: fields(link: "https://evil.example.com/x"), tag: .personal)?.link == "")
    }

    @Test("a calendar that is off contributes nothing, and the rest get their tag")
    func tagsDecideWhatIsRead() {
        let tags: [String: CalendarSetting] = ["family": .personal, "work": .work, "holidays": .off]
        let all = [
            fields(uid: "a", calendar: "family"),
            fields(uid: "b", calendar: "work"),
            fields(uid: "c", calendar: "holidays"),
            // A calendar the settings never mention is off.
            fields(uid: "d", calendar: "unknown"),
        ]

        let mapped = events(from: all) { tags[$0] ?? .off }

        #expect(mapped.map(\.calendar) == ["family", "work"])
        #expect(mapped.map(\.tag) == [.personal, .work])
    }

    @Test("a cancelled event is dropped even when its calendar is on")
    func cancelledDroppedInBatch() {
        let mapped = events(from: [fields(uid: "a"), fields(uid: "b", state: .canceled)]) { _ in .personal }
        #expect(mapped.map { $0.id.hasPrefix("a@") } == [true])
    }

    @Test("all-day events come through as all-day, so the rules never flag them")
    func allDay() {
        let mapped = event(from: fields(isAllDay: true), tag: .personal)!
        #expect(mapped.isAllDay)
        #expect(classify([mapped, event(from: fields(uid: "other"), tag: .work)!]) == [.none, .none])
    }
}
