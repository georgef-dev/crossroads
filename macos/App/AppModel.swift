// What the panel shows and what the keys do. All the decisions live in
// CrossroadsCore; this holds the current state and passes key presses to it.

import AppKit
import Observation

import CrossroadsCore

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var snapshot: Snapshot
    var settings: Settings
    var query = ""
    var days: Int
    var selection = 0
    var mode: Mode
    var showingSettings = false
    var settingsSelection = 0

    /// The key before this one, so gg works.
    private var lastKey = ""

    /// Set by the panel, so a key press can close it.
    var closePanel: () -> Void = {}

    private init() {
        let settings = Settings()
        self.settings = settings
        self.snapshot = sampleSnapshot()
        self.days = settings.defaultRange
        self.mode = initialMode(settings.keys)
    }

    var sections: [Section] {
        panelSections(snapshot, now: .now, days: days, query: query)
    }

    var rows: [SettingsRow] {
        settingsRows(settings, calendars: sampleCalendars)
    }

    /// The number beside the menu bar icon.
    var flagged: Int {
        flaggedCount(snapshot.events)
    }

    var status: StatusLine {
        statusLine(refreshing: false, snapshot: snapshot, runFailed: false)
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
            // Refreshing arrives with the real sources, in step 7.
            snapshot = sampleSnapshot()
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
        let action = settingsKeyAction(key, ctrl: ctrl, preset: settings.keys, previous: lastKey)

        switch action {
        case .up:
            settingsSelection = max(0, settingsSelection - 1)
        case .down:
            settingsSelection = min(rows.count - 1, settingsSelection + 1)
        case .previous, .next:
            guard let row = rows.first(where: { $0.index == settingsSelection }) else { break }
            settings = settings.cycling(row, by: action == .next ? 1 : -1)
            applySettings()
        case .reset:
            guard let row = rows.first(where: { $0.index == settingsSelection }) else { break }
            settings = settings.resetting(row)
            applySettings()
        case .jump(let edgeOf):
            settingsSelection = edgeOf == .first ? 0 : max(0, rows.count - 1)
        case .back:
            showingSettings = false
        case .pending, .ignore:
            break
        }
        return true
    }

    /// Settings that change the panel apply at once, not on the next open.
    private func applySettings() {
        if !ranges.contains(days) { days = settings.defaultRange }
        mode = initialMode(settings.keys)
    }

    private func open(_ item: Item?) {
        let link = linkOf(item)
        guard !link.isEmpty, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
        closePanel()
    }
}
