// When to fetch again, and what survives a failed fetch.

import Foundation
import Testing

import CrossroadsCore

@Suite("Refreshing")
struct RefreshingTests {
    @Test("a refresh is due once the interval has passed")
    func dueAfterInterval() {
        let last = moment(day: 17, hour: 9)
        #expect(!isRefreshDue(lastFetch: last, now: moment(day: 17, hour: 9, minute: 29), everyMinutes: 30))
        #expect(isRefreshDue(lastFetch: last, now: moment(day: 17, hour: 9, minute: 30), everyMinutes: 30))
        #expect(isRefreshDue(lastFetch: last, now: moment(day: 17, hour: 11), everyMinutes: 30))
    }

    @Test("nothing fetched yet means a refresh is due at once")
    func dueWhenNeverFetched() {
        #expect(isRefreshDue(lastFetch: nil, now: now, everyMinutes: 30))
    }

    @Test("an interval of zero means only refresh when asked")
    func manualOnly() {
        #expect(!isRefreshDue(lastFetch: nil, now: now, everyMinutes: 0))
        #expect(!isRefreshDue(lastFetch: moment(day: 1, hour: 9), now: now, everyMinutes: 0))
    }

    @Test("a failed fetch keeps the last good data and shows the errors")
    func keepsLastGood() {
        let good = Snapshot(
            fetchedAt: moment(day: 17, hour: 9),
            events: [event("meeting", day: 17, hour: 10)],
            mail: [MailMessage(id: "m", subject: "s", sender: "s", account: "a", link: "")]
        )

        let after = keepingLastGood(good, failedWith: ["Calendars: no access"])

        #expect(after.events.map(\.event.id) == ["meeting"])
        #expect(after.mail.count == 1)
        #expect(after.errors == ["Calendars: no access"])
        // The data is as old as it was, so the panel says so.
        #expect(after.fetchedAt == good.fetchedAt)
    }

    @Test("a first fetch that fails has nothing to keep, and says what went wrong")
    func nothingToKeep() {
        let after = keepingLastGood(nil, failedWith: ["Calendars: no access"])
        #expect(after.events.isEmpty)
        #expect(after.errors == ["Calendars: no access"])
        #expect(after.fetchedAt == nil)
    }
}
