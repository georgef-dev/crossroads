// The app's side of the panel: it owns the state, and carries out whatever
// that state asks for.
//
// Every decision lives in CrossroadsCore's PanelState, which is tested without
// a UI or an account. What is left here is the side effects: reading the
// sources, saving, opening a link, registering the shortcut.

import AppKit
import Observation

import CrossroadsCore

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var state: PanelState

    /// Demo mode draws made-up data, reads no account and saves nothing, so a
    /// screenshot can be taken without showing a real calendar or disturbing
    /// the real settings.
    private(set) var isDemo = false

    /// Set by the panel, so a key press can close it.
    var closePanel: () -> Void = {}
    /// Takes a shortcut from the system, and says whether it was given.
    var registerShortcut: (Shortcut) -> Bool = { _ in true }

    private let source = EventKitSource()
    private let gmail = GmailSource()
    private let store = SettingsStore()
    private var timer: Timer?

    private init() {
        let settings = SettingsStore().load()
        state = PanelState(settings: settings)
        state.mailConnected = !GoogleAuth.signedInAccounts().isEmpty
    }

    /// What the view should treat as now. Demo mode pins it to a fixed morning,
    /// so the day ahead is still ahead whenever a screenshot is taken.
    var referenceNow: Date {
        isDemo ? sampleNow() : .now
    }

    var sections: [Section] { state.sections(now: referenceNow) }
    var rows: [SettingsRow] { state.rows }
    var flagged: Int { flaggedCount(state.snapshot.events) }

    var status: StatusLine {
        statusLine(
            refreshing: state.refreshing,
            snapshot: state.snapshot.fetchedAt == nil ? nil : state.snapshot,
            runFailed: !state.snapshot.errors.isEmpty
        )
    }

    func panelDidOpen() {
        state.opened()
    }

    /// Handles a key press. Returns false when the panel should treat it as
    /// typing, so the search field gets it instead.
    func handle(key: String, ctrl: Bool, modifiers: KeyModifiers) -> Bool {
        let effects = state.handle(key: key, ctrl: ctrl, modifiers: modifiers, now: referenceNow)
        if effects.contains(.typing) { return false }
        for effect in effects { carry(out: effect) }
        return true
    }

    private func carry(out effect: PanelState.Effect) {
        switch effect {
        case .typing:
            break
        case .open(let link):
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        case .close:
            closePanel()
        case .refresh:
            Task { await refresh() }
        case .saveSettings:
            guard !isDemo else { break }
            store.save(state.settings)
            startTimer()
        case .registerShortcut(let shortcut):
            let took = isDemo || registerShortcut(shortcut)
            for next in state.shortcutRegistered(shortcut, took: took) {
                carry(out: next)
            }
        }
    }

    // ---- Reading the sources.

    /// Reads every source and rebuilds the snapshot. One source failing never
    /// hides the others: each reports its own error.
    func refresh() async {
        guard !isDemo else { return }
        state.refreshing = true
        defer { state.refreshing = false }

        let access = await source.requestAccess()
        var errors: [String] = []
        if case .denied = access.events { errors.append("Calendar access was refused") }
        if case .failed(let why) = access.events { errors.append("Calendars: \(why)") }
        if case .denied = access.reminders { errors.append("Reminders access was refused") }
        if case .failed(let why) = access.reminders { errors.append("Reminders: \(why)") }

        state.calendars = source.calendars()
        state.mailConnected = !GoogleAuth.signedInAccounts().isEmpty

        // The widest range, so changing the range needs no new fetch.
        let widest = ranges.max() ?? defaultRange
        let events = source.events(from: .now, days: widest, settings: state.settings)
        let reminders = await source.reminders(settings: state.settings)
        let (mail, mailErrors) = await gmail.unread()
        errors += mailErrors

        // Nothing came back at all, so keep what was already on screen rather
        // than blanking the panel over a passing failure.
        let readNothing = events.isEmpty && reminders.isEmpty && mail.isEmpty
        if readNothing && !errors.isEmpty && state.snapshot.fetchedAt != nil {
            state.snapshot = keepingLastGood(state.snapshot, failedWith: errors)
        } else {
            state.snapshot = buildSnapshot(
                fetchedAt: .now,
                events: events,
                reminders: reminders,
                calendarNames: source.calendarNames(),
                mail: mail,
                errors: errors
            )
        }
        state.selection = min(state.selection, max(0, itemCount(sections) - 1))
        startTimer()
    }

    /// Fetches again every so often, and once more when the Mac wakes, because
    /// a timer does not fire while it is asleep.
    func startTimer() {
        timer?.invalidate()
        timer = nil
        guard !isDemo, state.settings.refreshMinutes > 0 else { return }
        let every = TimeInterval(state.settings.refreshMinutes) * 60
        timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.refreshIfDue() }
        }
    }

    /// Refreshes only when the interval has really passed, so waking twice in
    /// a minute does not fetch twice.
    func refreshIfDue() async {
        guard isRefreshDue(
            lastFetch: state.snapshot.fetchedAt,
            now: .now,
            everyMinutes: state.settings.refreshMinutes
        ) else { return }
        await refresh()
    }

    /// Made-up data, in place of every real source.
    func startDemo() {
        isDemo = true
        state = PanelState(settings: sampleSettings, snapshot: sampleSnapshot(now: sampleNow()))
        state.calendars = sampleCalendars
        state.mailConnected = true
    }
}
