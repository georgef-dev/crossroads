// Where the settings live between launches.
//
// Each setting is its own UserDefaults key, so writing one cannot disturb
// another (specs/Settings.tla, OtherSettingsSurvive). The tags are one
// dictionary, written whole, which is this platform's answer to
// ConfigIsAlwaysWhole.

import Foundation

import CrossroadsCore

struct SettingsStore {
    private enum Key {
        static let refreshMinutes = "refreshMinutes"
        static let keys = "keys"
        static let defaultRange = "defaultRange"
        static let shortcut = "shortcut"
        static let tags = "tags"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Settings {
        Settings(
            refreshMinutes: defaults.object(forKey: Key.refreshMinutes) as? Int,
            keys: defaults.string(forKey: Key.keys),
            defaultRange: defaults.object(forKey: Key.defaultRange) as? Int,
            shortcut: shortcut() ?? .standard,
            tags: tags()
        )
    }

    func save(_ settings: Settings) {
        defaults.set(settings.refreshMinutes, forKey: Key.refreshMinutes)
        defaults.set(settings.keys.rawValue, forKey: Key.keys)
        defaults.set(settings.defaultRange, forKey: Key.defaultRange)
        write(settings.shortcut, forKey: Key.shortcut)
        write(settings.tags.mapValues(\.rawValue), forKey: Key.tags)
    }

    private func shortcut() -> Shortcut? {
        guard let data = defaults.data(forKey: Key.shortcut) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    /// A calendar the stored tags do not mention is off, so an unreadable or
    /// missing value simply means nothing is switched on.
    private func tags() -> [String: CalendarSetting] {
        guard let data = defaults.data(forKey: Key.tags),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored.compactMapValues(CalendarSetting.init(rawValue:))
    }

    private func write<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
