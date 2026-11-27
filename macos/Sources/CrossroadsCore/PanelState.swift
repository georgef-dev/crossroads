// Everything the panel remembers, and what each key press does to it.
//
// This is the whole decision layer, with no Apple framework in sight, so
// `swift test` covers it. The app owns one of these and carries out whatever
// it asks for: opening a link, saving, registering a shortcut, fetching again.
//
// Keeping the decisions here and the side effects in the app is what makes the
// panel's behaviour testable at all. The drawing is still not.

import Foundation

public struct PanelState: Sendable {
    public var snapshot: Snapshot
    public var settings: Settings
    /// Nil while the calendars are still being read.
    public var calendars: [CalendarInfo]?
    public var query = ""
    public var days: Int
    public var selection = 0
    public var mode: Mode
    public var showingSettings = false
    public var settingsSelection = 0
    /// Waiting for the next key to become the new shortcut.
    public var capturingShortcut = false
    /// A shortcut another app already holds, so the settings can say so.
    public var shortcutRefused: Shortcut?
    /// Whether any mail account is connected.
    public var mailConnected = false
    public var refreshing = false

    /// The key before this one, so gg works.
    private var lastKey = ""

    public init(settings: Settings = Settings(), snapshot: Snapshot = Snapshot()) {
        self.settings = settings
        self.snapshot = snapshot
        self.days = settings.defaultRange
        self.mode = initialMode(settings.keys)
    }

    /// What the app has to do after a key press. The panel decides; the app acts.
    public enum Effect: Hashable, Sendable {
        /// The panel should treat the key as typing into the search instead.
        case typing
        case open(link: String)
        case close
        case refresh
        case saveSettings
        /// Take this shortcut from the system, keeping the old one if it refuses.
        case registerShortcut(Shortcut)
    }

    public func sections(now: Date, calendar: Calendar = .current) -> [Section] {
        panelSections(
            snapshot,
            now: now,
            days: days,
            query: query,
            mailConnected: mailConnected,
            calendar: calendar
        )
    }

    public var rows: [SettingsRow] {
        settingsRows(settings, calendars: calendars)
    }

    /// Called when the panel opens, so it always opens the way the preset says.
    public mutating func opened() {
        mode = initialMode(settings.keys)
        selection = 0
        lastKey = ""
        capturingShortcut = false
    }

    /// Handles one key press and returns whatever the app must now do.
    public mutating func handle(
        key: String,
        ctrl: Bool = false,
        modifiers: KeyModifiers = [],
        now: Date,
        calendar: Calendar = .current
    ) -> [Effect] {
        defer { lastKey = key }
        if showingSettings {
            return handleSettings(key: key, ctrl: ctrl, modifiers: modifiers)
        }

        let sections = sections(now: now, calendar: calendar)
        let action = keyAction(key, ctrl: ctrl, preset: settings.keys, mode: mode, previous: lastKey)

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
            let link = linkOf(itemAt(sections, index: selection))
            return link.isEmpty ? [] : [.open(link: link), .close]
        case .settings:
            showingSettings = true
            settingsSelection = 0
        case .refresh:
            return [.refresh]
        case .clearOrClose:
            if query.isEmpty { return [.close] }
            query = ""
            selection = 0
        case .close:
            return [.close]
        case .normalMode:
            mode = .normal
        case .insertMode:
            mode = .insert
        case .pending, .ignore:
            break
        case .typing:
            return [.typing]
        }
        return []
    }

    private mutating func handleSettings(
        key: String,
        ctrl: Bool,
        modifiers: KeyModifiers
    ) -> [Effect] {
        if capturingShortcut {
            return capture(key: key, ctrl: ctrl, modifiers: modifiers)
        }

        let rows = self.rows
        let action = settingsKeyAction(key, ctrl: ctrl, preset: settings.keys, previous: lastKey)
        let row = rows.first { $0.index == settingsSelection }

        switch action {
        case .up:
            settingsSelection = max(0, settingsSelection - 1)
        case .down:
            settingsSelection = min(max(0, rows.count - 1), settingsSelection + 1)
        case .previous, .next:
            guard let row else { break }
            // The shortcut is captured from a key press, not cycled.
            if row.kind == .shortcut {
                capturingShortcut = true
                shortcutRefused = nil
                break
            }
            settings = settings.cycling(row, by: action == .next ? 1 : -1)
            return applied(row)
        case .reset:
            guard let row else { break }
            settings = settings.resetting(row)
            return applied(row)
        case .jump(let edgeOf):
            settingsSelection = edgeOf == .first ? 0 : max(0, rows.count - 1)
        case .back:
            showingSettings = false
            capturingShortcut = false
        case .pending, .ignore:
            break
        }
        return []
    }

    /// The next key becomes the shortcut, if it can be one. Escape gives up.
    private mutating func capture(
        key: String,
        ctrl: Bool,
        modifiers: KeyModifiers
    ) -> [Effect] {
        capturingShortcut = false
        guard key != "Escape" else { return [] }
        guard let wanted = Shortcut.from(
            control: ctrl,
            option: modifiers.contains(.option),
            shift: modifiers.contains(.shift),
            command: modifiers.contains(.command),
            key: key.count == 1 ? key.uppercased() : key
        ) else { return [] }

        // The app says whether the system handed it over. Until it does, the
        // old shortcut stays, so there is never a moment with none.
        return [.registerShortcut(wanted)]
    }

    /// Accepts a shortcut the system has given us, or records that it refused.
    public mutating func shortcutRegistered(_ shortcut: Shortcut, took: Bool) -> [Effect] {
        guard took else {
            shortcutRefused = shortcut
            return []
        }
        settings.shortcut = shortcut
        shortcutRefused = nil
        return [.saveSettings]
    }

    /// What a changed setting means beyond saving it.
    private mutating func applied(_ row: SettingsRow) -> [Effect] {
        if !ranges.contains(days) { days = settings.defaultRange }
        mode = initialMode(settings.keys)
        var effects: [Effect] = [.saveSettings]
        // Only switching a calendar on or off changes what there is to read.
        if case .calendar = row.kind { effects.append(.refresh) }
        if row.kind == .shortcut { effects.append(.registerShortcut(settings.shortcut)) }
        return effects
    }
}

/// The modifiers held down with a key, for capturing a shortcut.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let option = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let command = KeyModifiers(rawValue: 1 << 2)
}
