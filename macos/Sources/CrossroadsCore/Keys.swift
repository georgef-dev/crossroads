// Default and vim keys, gg and G, and moving the selection across sections
// and within the mail grid. Ported from omarchy/plugin/Model.js.

import Foundation

public enum KeyPreset: String, Codable, Sendable, CaseIterable {
    case `default`
    case vim
}

/// An unknown preset falls back to the default one.
public func keyPreset(_ value: String?) -> KeyPreset {
    KeyPreset(rawValue: value ?? "") ?? .default
}

/// Vim keys have two modes; the default preset is always in insert.
public enum Mode: String, Sendable {
    case insert
    case normal
}

/// Vim keys open in normal mode, ready to move; default keys open ready to search.
public func initialMode(_ preset: KeyPreset) -> Mode {
    preset == .vim ? .normal : .insert
}

public enum Direction: String, Sendable, CaseIterable {
    case up
    case down
    case left
    case right
}

public enum Edge: String, Sendable {
    case first
    case last
}

/// What a key press does in the panel.
public enum PanelAction: Hashable, Sendable {
    case move(Direction)
    case rangeNext
    case rangePrev
    case open
    case settings
    case refresh
    case clearOrClose
    case normalMode
    case insertMode
    case close
    case jump(Edge)
    /// The first g of gg, waiting for the second.
    case pending
    /// The key does nothing, rather than typing into the search.
    case ignore
    /// The panel should treat the key as typing.
    case typing
}

/// What a key press does, or `.typing` when the panel should treat it as typing.
/// `key` is a name ("Up", "Escape", "Tab", "Backtab", "Return", ...) or the
/// character typed. `previous` is the key before, for gg.
public func keyAction(
    _ key: String,
    ctrl: Bool = false,
    preset: KeyPreset = .default,
    mode: Mode = .insert,
    previous: String = ""
) -> PanelAction {
    let inNormalMode = preset == .vim && mode == .normal

    if ctrl && key == "," { return .settings }
    if ctrl {
        if key == "r" || key == "R" { return .refresh }
        return inNormalMode ? .ignore : .typing
    }

    if let direction = arrows[key] { return .move(direction) }
    if key == "Tab" { return .rangeNext }
    if key == "Backtab" { return .rangePrev }
    if key == "Return" { return .open }

    guard preset == .vim else {
        return key == "Escape" ? .clearOrClose : .typing
    }
    if mode == .insert {
        return key == "Escape" ? .normalMode : .typing
    }

    // Normal mode. A single g waits for the second one, as in vim.
    if key == "g" { return previous == "g" ? .jump(.first) : .pending }
    // Other keys do nothing in normal mode rather than typing into the search.
    return normalModeKeys[key] ?? .ignore
}

private let arrows: [String: Direction] = [
    "Up": .up, "Down": .down, "Left": .left, "Right": .right,
]

private let normalModeKeys: [String: PanelAction] = [
    "h": .move(.left),
    "j": .move(.down),
    "k": .move(.up),
    "l": .move(.right),
    "G": .jump(.last),
    "i": .insertMode,
    "/": .insertMode,
    "Escape": .close,
]

/// The first or last item of the whole list, for gg and G.
public func edge(_ sections: [Section], _ which: Edge) -> Int {
    which == .last ? max(0, itemCount(sections) - 1) : 0
}

/// The selection after moving one step, across sections and within grids.
/// Moves that lead nowhere keep the current selection.
public func move(_ sections: [Section], from index: Int, _ direction: Direction) -> Int {
    guard let at = locate(sections, index) else {
        return itemCount(sections) > 0 ? 0 : index
    }
    let section = sections[at.section]
    let items = section.items
    let columns = max(1, section.columns)
    let position = at.position
    let row = position / columns
    let lastRow = (items.count - 1) / columns

    switch direction {
    case .left:
        return position % columns > 0 ? items[position - 1].index : index
    case .right:
        let notLastColumn = position % columns < columns - 1
        return notLastColumn && position + 1 < items.count ? items[position + 1].index : index
    case .down:
        if row < lastRow {
            return items[min(position + columns, items.count - 1)].index
        }
        let next = sections[(at.section + 1)...].first { !$0.items.isEmpty }
        return next?.items.first?.index ?? index
    case .up:
        if row > 0 {
            return items[position - columns].index
        }
        let previous = sections[..<at.section].last { !$0.items.isEmpty }
        return previous?.items.last?.index ?? index
    }
}

private func locate(_ sections: [Section], _ index: Int) -> (section: Int, position: Int)? {
    for (s, section) in sections.enumerated() {
        for (p, item) in section.items.enumerated() where item.index == index {
            return (s, p)
        }
    }
    return nil
}

// ---- Settings keys.

/// What a key press does in the settings view.
public enum SettingsAction: Hashable, Sendable {
    case up
    case down
    /// The previous or next value of the row the selection is on.
    case previous
    case next
    case back
    /// Put the row back to its default.
    case reset
    case jump(Edge)
    case pending
    case ignore
}

/// Settings has nothing to type into, so letters only move with the vim preset.
public func settingsKeyAction(
    _ key: String,
    ctrl: Bool = false,
    preset: KeyPreset = .default,
    previous: String = ""
) -> SettingsAction {
    if ctrl { return key == "," ? .back : .ignore }
    if let action = settingsKeys[key] { return action }
    guard preset == .vim else { return .ignore }
    if key == "g" { return previous == "g" ? .jump(.first) : .pending }
    return settingsVimKeys[key] ?? .ignore
}

private let settingsKeys: [String: SettingsAction] = [
    "Up": .up,
    "Down": .down,
    "Left": .previous,
    "Right": .next,
    "Return": .next,
    "Escape": .back,
    "Backspace": .reset,
]

private let settingsVimKeys: [String: SettingsAction] = [
    "h": .previous,
    "j": .down,
    "k": .up,
    "l": .next,
    "G": .jump(.last),
]
