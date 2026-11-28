// What the panel does with a key press.
//
// These cover the behaviour that used to live only in the app, where nothing
// could reach it: moving between views, changing settings, capturing a
// shortcut, and what the app is asked to do as a result.

import Foundation
import Testing

import CrossroadsCore

@Suite("Panel state")
struct PanelStateTests {
    let calendars = [
        CalendarInfo(id: "family", name: "Family", source: "iCloud", kind: .events),
        CalendarInfo(id: "work", name: "Work", source: "Google", kind: .events),
    ]

    func state(keys: KeyPreset = .default) -> PanelState {
        var state = PanelState(
            settings: Settings(keys: keys.rawValue),
            snapshot: buildSnapshot(
                events: [
                    Event(id: "a", calendar: "family", tag: .personal, title: "Dentist",
                          start: moment(day: 17, hour: 10), end: moment(day: 17, hour: 11),
                          isAllDay: false, status: .accepted,
                          link: "https://www.icloud.com/calendar/"),
                ],
                now: now,
                calendar: newYork
            )
        )
        state.calendars = calendars
        return state
    }

    @discardableResult
    func press(_ state: inout PanelState, _ key: String, ctrl: Bool = false,
               modifiers: KeyModifiers = []) -> [PanelState.Effect] {
        state.handle(key: key, ctrl: ctrl, modifiers: modifiers, now: now, calendar: newYork)
    }

    // ---- Moving about.

    @Test("Ctrl+, opens settings and Escape comes back")
    func settingsRoundTrip() {
        var state = state()
        press(&state, ",", ctrl: true)
        #expect(state.showingSettings)
        press(&state, "Escape")
        #expect(!state.showingSettings)
    }

    @Test("Escape clears a search before it closes the panel")
    func escapeClearsFirst() {
        var state = state()
        state.query = "dent"

        #expect(press(&state, "Escape").isEmpty)
        #expect(state.query == "")
        // Now that there is nothing to clear, it closes.
        #expect(press(&state, "Escape") == [.close])
    }

    @Test("Return opens the selected item and closes the panel")
    func returnOpens() {
        var state = state()
        let effects = press(&state, "Return")
        #expect(effects == [.open(link: "https://www.icloud.com/calendar/"), .close])
    }

    @Test("Return on nothing does nothing")
    func returnOnNothing() {
        var state = PanelState()
        #expect(press(&state, "Return").isEmpty)
    }

    @Test("Tab changes the range and puts the selection back to the top")
    func tabChangesRange() {
        var state = state()
        state.selection = 1
        press(&state, "Tab")
        #expect(state.days == 14)
        #expect(state.selection == 0)
    }

    @Test("Ctrl+R asks for a refresh")
    func ctrlR() {
        var state = state()
        #expect(press(&state, "r", ctrl: true) == [.refresh])
    }

    @Test("a letter is typing with default keys, and movement in vim normal mode")
    func typingVersusMoving() {
        var plain = state()
        #expect(press(&plain, "j") == [.typing])

        var vim = state(keys: .vim)
        #expect(vim.mode == .normal)
        #expect(press(&vim, "j").isEmpty)
        // i starts typing, and then j types too.
        press(&vim, "i")
        #expect(vim.mode == .insert)
        #expect(press(&vim, "j") == [.typing])
    }

    // ---- Settings.

    @Test("changing a calendar saves and fetches again")
    func calendarChange() {
        var state = state()
        press(&state, ",", ctrl: true)
        // Rows: refresh, keys, range, shortcut, then the calendars.
        state.settingsSelection = 4

        let effects = press(&state, "Right")

        #expect(state.settings.setting(for: "family") == .personal)
        #expect(effects == [.saveSettings, .refresh])
    }

    @Test("changing another setting saves without fetching")
    func otherSettingChange() {
        var state = state()
        press(&state, ",", ctrl: true)
        state.settingsSelection = 0

        let effects = press(&state, "Right")

        #expect(effects == [.saveSettings])
        #expect(state.settings.refreshMinutes != 60)
    }

    @Test("the selection cannot leave the list")
    func selectionStaysInRange() {
        var state = state()
        press(&state, ",", ctrl: true)
        for _ in 0..<20 { press(&state, "Down") }
        #expect(state.settingsSelection == state.rows.count - 1)
        for _ in 0..<20 { press(&state, "Up") }
        #expect(state.settingsSelection == 0)
    }

    // ---- The shortcut.

    @Test("the shortcut row listens, then takes the next key")
    func capturesAShortcut() {
        var state = state()
        press(&state, ",", ctrl: true)
        state.settingsSelection = 3

        press(&state, "Right")
        #expect(state.capturingShortcut)

        let effects = press(&state, "k", modifiers: [.command, .option])
        #expect(effects == [.registerShortcut(Shortcut(option: true, command: true, key: "K"))])
        #expect(!state.capturingShortcut)

        // Nothing changes until the system hands it over.
        #expect(state.settings.shortcut == .standard)
        let saved = state.shortcutRegistered(Shortcut(option: true, command: true, key: "K"), took: true)
        #expect(saved == [.saveSettings])
        #expect(state.settings.shortcut.label == "⌥⌘K")
    }

    @Test("a shortcut the system refuses leaves the old one alone and says so")
    func refusedShortcut() {
        var state = state()
        let wanted = Shortcut(command: true, key: "Q")

        let effects = state.shortcutRegistered(wanted, took: false)

        #expect(effects.isEmpty)
        #expect(state.settings.shortcut == .standard)
        #expect(state.shortcutRefused == wanted)
    }

    @Test("Escape gives up on capturing and keeps the old shortcut")
    func escapeDuringCapture() {
        var state = state()
        press(&state, ",", ctrl: true)
        state.settingsSelection = 3
        press(&state, "Right")

        #expect(press(&state, "Escape").isEmpty)
        #expect(!state.capturingShortcut)
        #expect(state.settings.shortcut == .standard)
    }

    @Test("a key that cannot be a shortcut is ignored, and capturing stops")
    func unusableShortcut() {
        var state = state()
        press(&state, ",", ctrl: true)
        state.settingsSelection = 3
        press(&state, "Right")

        // No modifier beyond shift, so this is not a shortcut.
        #expect(press(&state, "k", modifiers: [.shift]).isEmpty)
        #expect(!state.capturingShortcut)
        #expect(state.settings.shortcut == .standard)
    }

    // ---- Opening.

    @Test("the panel opens the way the preset says, every time")
    func openingMode() {
        var vim = state(keys: .vim)
        vim.mode = .insert
        vim.selection = 3
        vim.opened()
        #expect(vim.mode == .normal)
        #expect(vim.selection == 0)

        var plain = state()
        plain.opened()
        #expect(plain.mode == .insert)
    }
}
