// Ported from omarchy/plugin/tests/Settings.test.js. Spec: specs/Settings.tla.
//
// Two cases are not ported. parseListing read untrusted output from
// `crossroads calendars --json`, which the Mac has no equivalent of: EventKit
// hands back typed calendars. And withSetting existed because Omarchy saves
// every setting in one shell.json entry, so the plugin had to rebuild that
// entry without the widget id; the Mac gives each setting its own
// UserDefaults key. OtherSettingsSurvive is still tested below.

import Foundation
import Testing

import CrossroadsCore

private let calendars = [
    CalendarInfo(id: "gf@x.com", name: "Mine", source: "Google"),
    CalendarInfo(id: "holidays", name: "Holidays", source: "Google"),
    CalendarInfo(id: "/1/home/", name: "George", source: "iCloud"),
]

private let tags: [String: CalendarSetting] = ["gf@x.com": .personal, "/1/home/": .personal]

@Suite("Settings")
struct SettingsTests {
    @Test("Settings.TypeOK: every setting has a value, with safe defaults")
    func safeDefaults() {
        let fallbacks = Settings()
        #expect(fallbacks.refreshMinutes == 60)
        #expect(fallbacks.keys == .default)
        #expect(fallbacks.defaultRange == 7)

        let stored = Settings(refreshMinutes: 15, keys: "vim", defaultRange: 3)
        #expect(stored.refreshMinutes == 15)
        #expect(stored.keys == .vim)
        #expect(stored.defaultRange == 3)

        #expect(Settings(refreshMinutes: 0).refreshMinutes == 0)

        // A senseless stored value falls back rather than reaching the panel.
        let nonsense = Settings(refreshMinutes: -5, keys: "emacs", defaultRange: 5)
        #expect(nonsense.refreshMinutes == 0)
        #expect(nonsense.keys == .default)
        #expect(nonsense.defaultRange == 7)
    }

    @Test("Settings.OtherSettingsSurvive: changing one setting leaves every other setting as it was")
    func otherSettingsSurvive() {
        var generator = SeededGenerator(seed: 11)
        for _ in 0..<500 {
            let before = Settings(
                refreshMinutes: refreshOptions.randomElement(using: &generator)!,
                keys: KeyPreset.allCases.randomElement(using: &generator)!.rawValue,
                defaultRange: ranges.randomElement(using: &generator)!,
                shortcut: .standard,
                tags: tags
            )
            let rows = settingsRows(before, calendars: calendars)
            let row = rows.randomElement(using: &generator)!
            let step = Bool.random(using: &generator) ? 1 : -1

            let after = before.cycling(row, by: step)

            // Only the cycled row's own setting may differ.
            if case .refreshMinutes = row.kind {} else {
                #expect(after.refreshMinutes == before.refreshMinutes)
            }
            if case .keys = row.kind {} else {
                #expect(after.keys == before.keys)
            }
            if case .defaultRange = row.kind {} else {
                #expect(after.defaultRange == before.defaultRange)
            }
            #expect(after.shortcut == before.shortcut)
            if case .calendar(let changed) = row.kind {
                for calendar in calendars where calendar.id != changed.id {
                    #expect(after.setting(for: calendar.id) == before.setting(for: calendar.id))
                }
            } else {
                #expect(after.tags == before.tags)
            }
        }
    }

    @Test("values cycle through their options and wrap")
    func cycling() {
        #expect(cycle(refreshOptions, 60, step: 1) == 120)
        #expect(cycle(refreshOptions, 120, step: 1) == 0)
        #expect(cycle(refreshOptions, 0, step: -1) == 120)
        // An unknown value starts over.
        #expect(cycle(ranges, 5, step: 1) == 0)
    }

    @Test("settings rows: the general settings, the shortcut, then every calendar")
    func rows() {
        let settings = Settings(refreshMinutes: 30, keys: "vim", tags: tags)
        let rows = settingsRows(settings, calendars: calendars)

        #expect(rows.map(\.value) == ["30", "vim", "7", "⌥⌘C", "personal", "off", "personal"])
        #expect(rows.map(\.index) == [0, 1, 2, 3, 4, 5, 6])
        #expect(rows[0].options == ["0", "15", "30", "60", "120"])
        #expect(rows[1].options == ["default", "vim"])
        #expect(rows[2].options == ["0", "1", "3", "7", "14"])
        #expect(rows[4].options == ["off", "personal", "work"])

        if case .calendar(let calendar) = rows[6].kind {
            #expect(calendar.source == "iCloud")
            #expect(calendar.name == "George")
        } else {
            Issue.record("row 6 should be a calendar")
        }
    }

    @Test("settings rows: the shortcut shows ⌥⌘C until it is changed")
    func shortcutRow() {
        let row = settingsRows(Settings()).first { $0.kind == .shortcut }
        #expect(row?.value == "⌥⌘C")
    }

    @Test("settings rows: only the general settings and the shortcut while calendars are loading")
    func rowsWhileLoading() {
        #expect(settingsRows(Settings(), calendars: nil).count == 4)
    }

    @Test("settings keys: arrows in both presets, h/j/k/l only with vim")
    func settingsKeys() {
        for preset in KeyPreset.allCases {
            #expect(settingsKeyAction("Up", preset: preset) == .up)
            #expect(settingsKeyAction("Down", preset: preset) == .down)
            #expect(settingsKeyAction("Left", preset: preset) == .previous)
            #expect(settingsKeyAction("Right", preset: preset) == .next)
            #expect(settingsKeyAction("Return", preset: preset) == .next)
            #expect(settingsKeyAction("Escape", preset: preset) == .back)
            #expect(settingsKeyAction(",", ctrl: true, preset: preset) == .back)
        }
        #expect(
            ["h", "j", "k", "l"].map { settingsKeyAction($0, preset: .vim) }
                == [.previous, .down, .up, .next]
        )
        #expect(settingsKeyAction("j", preset: .default) == .ignore)
        #expect(settingsKeyAction("x", preset: .vim) == .ignore)
    }

    @Test("Ctrl+, opens settings from the main view, in every preset and mode")
    func opensSettings() {
        let combinations: [(KeyPreset, Mode)] = [(.default, .insert), (.vim, .insert), (.vim, .normal)]
        for (preset, mode) in combinations {
            #expect(keyAction(",", ctrl: true, preset: preset, mode: mode) == .settings)
        }
    }

    @Test("a calendar can go Off → Personal → Work from the keyboard")
    func cyclingACalendar() {
        var current = Settings()
        var seen: [String] = []
        for _ in 0..<3 {
            let row = settingsRows(current, calendars: calendars)
                .first { $0.kind == .calendar(calendars[1]) }!
            current = current.cycling(row, by: 1)
            seen.append(current.setting(for: calendars[1].id).rawValue)
        }
        #expect(seen == ["personal", "work", "off"])
    }

    @Test("changing one calendar leaves the others alone")
    func changingOneCalendar() {
        let before = Settings(tags: tags)
        let row = settingsRows(before, calendars: calendars)
            .first { $0.kind == .calendar(calendars[2]) }!

        let after = before.cycling(row, by: 1)

        #expect(after.setting(for: "/1/home/") == .work)
        #expect(after.setting(for: "gf@x.com") == .personal)
        #expect(after.setting(for: "holidays") == .off)
        // The settings it was given are untouched.
        #expect(before.setting(for: "/1/home/") == .personal)
    }

    @Test("gg and G jump to the first and last setting with vim keys")
    func ggInSettings() {
        #expect(settingsKeyAction("g", preset: .vim, previous: "") == .pending)
        #expect(settingsKeyAction("g", preset: .vim, previous: "g") == .jump(.first))
        #expect(settingsKeyAction("G", preset: .vim, previous: "") == .jump(.last))
        #expect(settingsKeyAction("G", preset: .default, previous: "") == .ignore)
        #expect(settingsKeyAction("g", preset: .default, previous: "g") == .ignore)
    }

    @Test("Backspace resets a row: the shortcut goes back to its default")
    func resetting() {
        #expect(settingsKeyAction("Backspace", preset: .default) == .reset)
        #expect(settingsKeyAction("Backspace", preset: .vim) == .reset)

        let changed = Settings(shortcut: Shortcut(control: true, key: "X"))
        let row = settingsRows(changed).first { $0.kind == .shortcut }!
        #expect(changed.resetting(row).shortcut == .standard)
    }

    @Test("a new shortcut is a modifier plus a letter, digit, F1–F12 or Space")
    func capturingAShortcut() {
        #expect(
            Shortcut.from(control: false, option: true, shift: false, command: true, key: "X")
                == Shortcut(option: true, command: true, key: "X")
        )
        #expect(
            Shortcut.from(control: true, option: true, shift: true, command: true, key: "F12")?.label
                == "⌃⌥⇧⌘F12"
        )
        #expect(Shortcut.from(control: false, option: false, shift: false, command: true, key: "SPACE")?.label == "⌘Space")
        #expect(Shortcut.from(control: true, option: false, shift: false, command: false, key: "7")?.label == "⌃7")

        // Not yet a shortcut: no modifier, only Shift, or an unsupported key.
        #expect(Shortcut.from(control: false, option: false, shift: false, command: false, key: "X") == nil)
        #expect(Shortcut.from(control: false, option: false, shift: true, command: false, key: "X") == nil)
        #expect(Shortcut.from(control: false, option: true, shift: false, command: true, key: "Command") == nil)
        #expect(Shortcut.from(control: false, option: false, shift: false, command: true, key: "RETURN") == nil)
        #expect(Shortcut.from(control: false, option: false, shift: false, command: true, key: "F13") == nil)
    }

    @Test("shortcuts read the way the Mac writes them")
    func shortcutLabels() {
        #expect(Shortcut.standard.label == "⌥⌘C")
        #expect(Shortcut(control: true, shift: true, key: "SPACE").label == "⌃⇧Space")
        #expect(Shortcut(option: true, command: true, key: "F5").label == "⌥⌘F5")
    }
}
