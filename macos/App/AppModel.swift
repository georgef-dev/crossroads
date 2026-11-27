// What the panel shows and what the keys do. All the decisions live in
// CrossroadsCore; this holds the current state and passes key presses to it.

import AppKit
import Observation

import CrossroadsCore

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var snapshot = Snapshot()
    var settings: Settings
    var query = ""
    var days: Int
    var selection = 0
    var mode: Mode
    var showingSettings = false
    var settingsSelection = 0
    var refreshing = false

    /// Demo mode draws made-up data, reads no account and saves nothing, so a
    /// screenshot can be taken without showing a real calendar or disturbing
    /// the real settings.
    private(set) var isDemo = false

    /// Nil until the calendars have been read, which is what the settings view
    /// shows "loading" for.
    var calendars: [CalendarInfo]?

    /// The key before this one, so gg works.
    private var lastKey = ""

    /// Set by the panel, so a key press can close it.
    var closePanel: () -> Void = {}

    private let source = EventKitSource()
    private let gmail = GmailSource()
    private let store = SettingsStore()
    private var timer: Timer?

    /// Set while the settings view is waiting for the next key to become the
    /// new shortcut.
    var capturingShortcut = false

    /// Told about a new shortcut, so the app can register it.
    var shortcutChanged: (Shortcut) -> Bool = { _ in true }

    private init() {
        let settings = SettingsStore().load()
        self.settings = settings
        self.days = settings.defaultRange
        self.mode = initialMode(settings.keys)
    }

    /// What the view should treat as now. Demo mode pins it to a fixed morning,
    /// so the day ahead is still ahead whenever the screenshot is taken.
    var referenceNow: Date {
        isDemo ? sampleNow() : .now
    }

    /// Made-up data, in place of every real source.
    func startDemo() {
        isDemo = true
        settings = sampleSettings
        calendars = sampleCalendars
        snapshot = sampleSnapshot(now: sampleNow())
        days = settings.defaultRange
        mode = initialMode(settings.keys)
        selection = 0
    }

    var sections: [Section] {
        panelSections(
            snapshot,
            now: referenceNow,
            days: days,
            query: query,
            // Demo mode shows mail without anybody being signed in.
            mailConnected: isDemo || !GoogleAuth.signedInAccounts().isEmpty
        )
    }

    var rows: [SettingsRow] {
        settingsRows(settings, calendars: calendars)
    }

    /// The number beside the menu bar icon.
    var flagged: Int {
        flaggedCount(snapshot.events)
    }

    var status: StatusLine {
        statusLine(
            refreshing: refreshing,
            snapshot: snapshot.fetchedAt == nil ? nil : snapshot,
            runFailed: !snapshot.errors.isEmpty
        )
    }

    /// Reads every source and rebuilds the snapshot. One source failing never
    /// hides the others: each reports its own error.
    func refresh() async {
        guard !isDemo else {
            snapshot = sampleSnapshot(now: sampleNow())
            return
        }
        refreshing = true
        defer { refreshing = false }

        let access = await source.requestAccess()
        var errors: [String] = []
        if case .denied = access.events { errors.append("Calendar access was refused") }
        if case .failed(let why) = access.events { errors.append("Calendars: \(why)") }
        if case .denied = access.reminders { errors.append("Reminders access was refused") }
        if case .failed(let why) = access.reminders { errors.append("Reminders: \(why)") }

        calendars = source.calendars()

        // The widest range, so changing the range needs no new fetch.
        let widest = ranges.max() ?? defaultRange
        let events = source.events(from: .now, days: widest, settings: settings)
        let reminders = await source.reminders(settings: settings)
        let (mail, mailErrors) = await gmail.unread()
        errors += mailErrors

        // Nothing came back at all, so keep what was already on screen rather
        // than blanking the panel over a passing failure.
        let readNothing = events.isEmpty && reminders.isEmpty && mail.isEmpty
        if readNothing && !errors.isEmpty && snapshot.fetchedAt != nil {
            snapshot = keepingLastGood(snapshot, failedWith: errors)
        } else {
            snapshot = buildSnapshot(
                fetchedAt: .now,
                events: events,
                reminders: reminders,
                calendarNames: source.calendarNames(),
                mail: mail,
                errors: errors
            )
        }
        selection = min(selection, max(0, itemCount(sections) - 1))
        startTimer()
    }

    /// Fetches again every so often, and once more when the Mac wakes, because
    /// a timer does not fire while it is asleep.
    func startTimer() {
        timer?.invalidate()
        timer = nil
        guard !isDemo, settings.refreshMinutes > 0 else { return }
        let every = TimeInterval(settings.refreshMinutes) * 60
        timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.refreshIfDue() }
        }
    }

    /// Refreshes only when the interval has really passed, so waking from
    /// sleep twice in a minute does not fetch twice.
    func refreshIfDue() async {
        guard isRefreshDue(
            lastFetch: snapshot.fetchedAt,
            now: .now,
            everyMinutes: settings.refreshMinutes
        ) else { return }
        await refresh()
    }

    /// Called when the panel opens, so it always opens the way the preset says.
    func panelDidOpen() {
        mode = initialMode(settings.keys)
        selection = 0
        lastKey = ""
    }

    /// Handles a key press. Returns false when the panel should treat it as
    /// typing, so the search field gets it instead.
    func handle(key: String, ctrl: Bool) -> Bool {
        defer { lastKey = key }
        if showingSettings {
            return handleSettings(key: key, ctrl: ctrl)
        }

        let action = keyAction(
            key,
            ctrl: ctrl,
            preset: settings.keys,
            mode: mode,
            previous: lastKey
        )

        switch action {
        case .move(let direction):
            selection = move(sections, from: selection, direction)
        case .jump(let edgeOf):
            selection = edge(sections, edgeOf)
        case .rangeNext:
            days = nextRange(from: days, step: 1, wrap: true)
            selection = 0
        case .rangePrev:
            days = nextRange(from: days, step: -1, wrap: true)
            selection = 0
        case .open:
            open(itemAt(sections, index: selection))
        case .settings:
            showingSettings = true
            settingsSelection = 0
        case .refresh:
            Task { await refresh() }
        case .clearOrClose:
            if query.isEmpty { closePanel() } else { query = "" }
        case .close:
            closePanel()
        case .normalMode:
            mode = .normal
        case .insertMode:
            mode = .insert
        case .pending, .ignore:
            break
        case .typing:
            return false
        }
        return true
    }

    private func handleSettings(key: String, ctrl: Bool) -> Bool {
        let rows = self.rows
        if capturingShortcut {
            capture(key: key, ctrl: ctrl)
            return true
        }
        let action = settingsKeyAction(key, ctrl: ctrl, preset: settings.keys, previous: lastKey)

        switch action {
        case .up:
            settingsSelection = max(0, settingsSelection - 1)
        case .down:
            settingsSelection = min(rows.count - 1, settingsSelection + 1)
        case .previous, .next:
            guard let row = rows.first(where: { $0.index == settingsSelection }) else { break }
            // The shortcut is captured from a key press, not cycled.
            if case .shortcut = row.kind {
                capturingShortcut = true
                break
            }
            settings = settings.cycling(row, by: action == .next ? 1 : -1)
            applySettings(changed: row)
        case .reset:
            guard let row = rows.first(where: { $0.index == settingsSelection }) else { break }
            settings = settings.resetting(row)
            applySettings(changed: row)
        case .jump(let edgeOf):
            settingsSelection = edgeOf == .first ? 0 : max(0, rows.count - 1)
        case .back:
            showingSettings = false
        case .pending, .ignore:
            break
        }
        return true
    }

    /// The next key pressed becomes the shortcut, if it can be one and the
    /// system will give it to us. Escape gives up and keeps the old one.
    private func capture(key: String, ctrl: Bool) {
        defer { capturingShortcut = false }
        guard key != "Escape" else { return }
        guard let wanted = Shortcut.from(
            control: ctrl,
            option: pressedModifiers.contains(.option),
            shift: pressedModifiers.contains(.shift),
            command: pressedModifiers.contains(.command),
            key: key.count == 1 ? key.uppercased() : key
        ) else { return }

        // Only keep it if the system actually hands it over, so there is never
        // a moment with no shortcut (Settings.ShortcutNeverConflicts).
        guard shortcutChanged(wanted) else {
            shortcutRefused = wanted
            return
        }
        settings.shortcut = wanted
        shortcutRefused = nil
        store.save(settings)
    }

    /// The modifiers held down right now, which the panel keeps up to date.
    var pressedModifiers: Modifiers = []

    /// A shortcut another app already holds, so the settings can say so.
    var shortcutRefused: Shortcut?

    struct Modifiers: OptionSet {
        let rawValue: Int
        static let option = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let command = Modifiers(rawValue: 1 << 2)
    }

    /// Settings that change the panel apply at once, not on the next open, and
    /// are kept for the next launch.
    private func applySettings(changed row: SettingsRow) {
        if !ranges.contains(days) { days = settings.defaultRange }
        mode = initialMode(settings.keys)
        // Demo mode must not touch the real settings or any account.
        guard !isDemo else { return }
        store.save(settings)
        // Only switching a calendar on or off changes what there is to read,
        // so the other settings never set off a fetch.
        if case .calendar = row.kind {
            Task { await refresh() }
        }
        if case .refreshMinutes = row.kind {
            startTimer()
        }
        if case .shortcut = row.kind {
            _ = shortcutChanged(settings.shortcut)
        }
    }

    private func open(_ item: Item?) {
        let link = linkOf(item)
        guard !link.isEmpty, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
        closePanel()
    }
}
