// When to fetch again, and what to show when a fetch goes wrong.
//
// Ported from the service in omarchy/plugin/Service.qml, which fetches on a
// timer and holds the last good snapshot. The same two rules apply here: a
// refresh interval of zero means only refresh when asked, and a failed fetch
// never throws away data that is still worth showing.

import Foundation

/// Whether the timer should fetch again. An interval of zero is manual only.
public func isRefreshDue(lastFetch: Date?, now: Date, everyMinutes: Int) -> Bool {
    guard everyMinutes > 0 else { return false }
    guard let lastFetch else { return true }
    return now.timeIntervalSince(lastFetch) >= Double(everyMinutes) * 60
}

/// What to show after a fetch that failed: the last good data, with the errors
/// alongside it, so one broken source cannot blank the panel. `fetchedAt`
/// stays as it was, because the data is still as old as it was.
public func keepingLastGood(_ previous: Snapshot?, failedWith errors: [String]) -> Snapshot {
    guard let previous else {
        return Snapshot(errors: errors)
    }
    return Snapshot(
        fetchedAt: previous.fetchedAt,
        events: previous.events,
        overlaps: previous.overlaps,
        reminders: previous.reminders,
        mail: previous.mail,
        errors: errors
    )
}
