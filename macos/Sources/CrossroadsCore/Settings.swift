// Reading and changing settings, calendar tags, and the shortcut.
// Spec: specs/Settings.tla. Ported from the settings part of omarchy/plugin/Model.js.
//
// Omarchy keeps the settings in one shell.json entry, so the plugin rewrites
// the whole entry on every save and takes care never to carry the widget id
// into it. The Mac gives each setting its own UserDefaults key, so that care
// is not needed here: Settings is a value type, and changing one field cannot
// reach another.

import Foundation

public let refreshOptions = [0, 15, 30, 60, 120]

/// What a calendar is set to. A calendar the settings don't mention is off.
public enum CalendarSetting: String, Codable, Sendable, CaseIterable {
    case off
    case personal
    case work

    /// The tag its events carry, or nothing when the calendar is off.
    public var tag: Tag? {
        Tag(rawValue: rawValue)
    }
}

/// Whether a calendar holds events or reminders. Both are calendars as far as
/// EventKit is concerned, and they can share a name, so the settings say which.
public enum CalendarKind: String, Sendable {
    case events
    case reminders
}

/// One calendar the Mac can see.
public struct CalendarInfo: Hashable, Sendable {
    /// EventKit's `calendarIdentifier`.
    public let id: String
    public let name: String
    /// The account it comes from, like "iCloud" or a Google address. Names
    /// repeat across accounts, so this is what tells two of them apart.
    public let source: String
    public let kind: CalendarKind

    public init(id: String, name: String, source: String, kind: CalendarKind = .events) {
        self.id = id
        self.name = name
        self.source = source
        self.kind = kind
    }
}

public struct Settings: Hashable, Sendable {
    public var refreshMinutes: Int
    public var keys: KeyPreset
    public var defaultRange: Int
    public var shortcut: Shortcut
    /// Keyed by `CalendarInfo.id`. A calendar that is missing is off.
    public var tags: [String: CalendarSetting]

    /// Every setting gets a safe default, so a missing or senseless stored
    /// value can never leave the panel without one.
    public init(
        refreshMinutes: Int? = nil,
        keys: String? = nil,
        defaultRange: Int? = nil,
        shortcut: Shortcut = .standard,
        tags: [String: CalendarSetting] = [:]
    ) {
        self.refreshMinutes = max(0, refreshMinutes ?? 60)
        self.keys = keyPreset(keys)
        if let range = defaultRange, ranges.contains(range) {
            self.defaultRange = range
        } else {
            self.defaultRange = CrossroadsCore.defaultRange
        }
        self.shortcut = shortcut
        self.tags = tags
    }

    /// What a calendar is set to, which is off unless the settings say otherwise.
    public func setting(for calendarID: String) -> CalendarSetting {
        tags[calendarID] ?? .off
    }
}

/// The next or previous option, wrapping around. An unknown value starts over.
public func cycle<Value: Equatable>(_ options: [Value], _ value: Value, step: Int) -> Value {
    guard let index = options.firstIndex(of: value) else { return options[0] }
    let count = options.count
    return options[((index + step) % count + count) % count]
}

// ---- The rows the settings view shows.

public struct SettingsRow: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case refreshMinutes
        case keys
        case defaultRange
        case shortcut
        case calendar(CalendarInfo)
    }

    public let kind: Kind
    public let index: Int
    /// The values the row cycles through, as labels. Empty for the shortcut,
    /// which is captured rather than chosen.
    public let options: [String]
    public let value: String
}

/// What the settings view lists: the general settings, the shortcut, then
/// every calendar the Mac can see. `calendars` is nil while they load.
public func settingsRows(_ settings: Settings, calendars: [CalendarInfo]? = nil) -> [SettingsRow] {
    var kinds: [(SettingsRow.Kind, [String], String)] = [
        (.refreshMinutes, refreshOptions.map(String.init), String(settings.refreshMinutes)),
        (.keys, KeyPreset.allCases.map(\.rawValue), settings.keys.rawValue),
        (.defaultRange, ranges.map(String.init), String(settings.defaultRange)),
        (.shortcut, [], settings.shortcut.label),
    ]
    for calendar in calendars ?? [] {
        kinds.append((
            .calendar(calendar),
            CalendarSetting.allCases.map(\.rawValue),
            settings.setting(for: calendar.id).rawValue
        ))
    }
    return kinds.enumerated().map { index, row in
        SettingsRow(kind: row.0, index: index, options: row.1, value: row.2)
    }
}

extension Settings {
    /// The settings after cycling one row's value. The shortcut is captured
    /// from a key press instead, so it does not cycle.
    public func cycling(_ row: SettingsRow, by step: Int) -> Settings {
        var next = self
        switch row.kind {
        case .refreshMinutes:
            next.refreshMinutes = cycle(refreshOptions, refreshMinutes, step: step)
        case .keys:
            next.keys = cycle(KeyPreset.allCases, keys, step: step)
        case .defaultRange:
            next.defaultRange = cycle(ranges, defaultRange, step: step)
        case .shortcut:
            break
        case .calendar(let calendar):
            next.tags[calendar.id] = cycle(
                CalendarSetting.allCases,
                setting(for: calendar.id),
                step: step
            )
        }
        return next
    }

    /// The settings after putting one row back to its default.
    public func resetting(_ row: SettingsRow) -> Settings {
        var next = self
        switch row.kind {
        case .refreshMinutes: next.refreshMinutes = 60
        case .keys: next.keys = .default
        case .defaultRange: next.defaultRange = CrossroadsCore.defaultRange
        case .shortcut: next.shortcut = .standard
        case .calendar(let calendar): next.tags[calendar.id] = .off
        }
        return next
    }
}

// ---- The shortcut.

/// The global shortcut that opens the panel. Omarchy writes this as Hyprland
/// text ("SUPER + ALT + C"); the Mac holds the modifiers and the key, and the
/// app registers them with the system.
public struct Shortcut: Hashable, Codable, Sendable {
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool
    /// "A"-"Z", "0"-"9", "F1"-"F12" or "SPACE".
    public var key: String

    public init(control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false, key: String) {
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
        self.key = key
    }

    /// ⌥⌘C, the Mac's answer to Super+Alt+C.
    public static let standard = Shortcut(option: true, command: true, key: "C")

    /// How the Mac writes it, in the order the system shows modifiers.
    public var label: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + (key == "SPACE" ? "Space" : key)
    }

    /// The shortcut a key press makes, or nothing while it isn't one yet.
    /// A shortcut needs Control, Option or Command: Shift alone is not enough,
    /// and the key must be one the system can register.
    public static func from(
        control: Bool,
        option: Bool,
        shift: Bool,
        command: Bool,
        key: String
    ) -> Shortcut? {
        guard control || option || command, isRegisterable(key) else { return nil }
        return Shortcut(control: control, option: option, shift: shift, command: command, key: key)
    }

    /// Letters, digits, F1-F12 and Space. Anything else, a modifier on its own
    /// included, is not a shortcut.
    static func isRegisterable(_ key: String) -> Bool {
        if key == "SPACE" { return true }
        if key.count == 1, let first = key.first, first.isASCII, first.isLetter || first.isNumber {
            return first.isUppercase || first.isNumber
        }
        if key.first == "F", let number = Int(key.dropFirst()) {
            return (1...12).contains(number)
        }
        return false
    }
}
