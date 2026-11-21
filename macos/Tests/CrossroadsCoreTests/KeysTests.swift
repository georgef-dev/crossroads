// Ported from omarchy/plugin/tests/Keys.test.js.

import Foundation
import Testing

import CrossroadsCore

/// Sections shaped like panelSections output. Only the indices, the columns and
/// the counts matter to `move`, so the values are filler.
func layout(_ shapes: [(SectionKey, Int)]) -> [Section] {
    var index = 0
    return shapes.map { key, count in
        let items = (0..<count).map { _ -> Item in
            let item = Item(
                value: .mail(MailMessage(id: "\(index)", subject: "", sender: "", account: "", link: "")),
                index: index
            )
            index += 1
            return item
        }
        return Section(key: key, columns: key == .mail ? mailColumns : 1, items: items)
    }
}

/// Indices: overlaps 0-1, today 2-3, mail 4-8 (rows: 4 5 / 6 7 / 8).
private let threeSections = layout([(.overlaps, 2), (.today, 2), (.mail, 5)])

private func press(_ sections: [Section], _ start: Int, _ directions: Direction...) -> Int {
    directions.reduce(start) { move(sections, from: $0, $1) }
}

@Suite("Keys and selection")
struct KeysTests {
    @Test("left and right move between the mail columns")
    func acrossColumns() {
        #expect(press(threeSections, 4, .right) == 5)
        #expect(press(threeSections, 5, .left) == 4)
        #expect(press(threeSections, 7, .left) == 6)
    }

    @Test("left and right stop at the edges of a row and never leave the grid")
    func gridEdges() {
        #expect(press(threeSections, 4, .left) == 4)
        #expect(press(threeSections, 5, .right) == 5)
        #expect(press(threeSections, 8, .right) == 8)
    }

    @Test("left and right do nothing in single-column lists")
    func listsIgnoreSideways() {
        #expect(press(threeSections, 2, .left) == 2)
        #expect(press(threeSections, 2, .right) == 2)
    }

    @Test("up and down move through lists and across sections")
    func acrossSections() {
        #expect(press(threeSections, 0, .down, .down, .down) == 3)
        #expect(press(threeSections, 3, .down) == 4)
        #expect(press(threeSections, 4, .up) == 3)
        #expect(press(threeSections, 0, .up) == 0)
    }

    @Test("up and down move by whole rows in the mail grid")
    func wholeRows() {
        #expect(press(threeSections, 5, .down) == 7)
        #expect(press(threeSections, 7, .up) == 5)
        #expect(press(threeSections, 5, .up) == 3)
        // The last row is short: moving down from its column lands on its last card.
        #expect(press(threeSections, 7, .down) == 8)
        #expect(press(threeSections, 8, .down) == 8)
    }

    @Test("empty sections are skipped")
    func skipsEmpty() {
        let withEmpty = layout([(.today, 1), (.events, 0), (.mail, 2)])
        #expect(press(withEmpty, 0, .down) == 1)
        #expect(press(withEmpty, 1, .up) == 0)
    }

    @Test("property: the selection is always on a real item, whatever keys are pressed")
    func selectionStaysReal() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<300 {
            let shapes: [(SectionKey, Int)] = [.mail, .overlaps, .today, .events].map {
                ($0, Int.random(in: 0..<6, using: &generator))
            }
            let shaped = layout(shapes)
            let count = itemCount(shaped)
            var index = 0
            for _ in 0..<40 {
                let direction = Direction.allCases.randomElement(using: &generator)!
                index = move(shaped, from: index, direction)
                if count > 0 {
                    #expect(index >= 0 && index < count, "index \(index) of \(count)")
                }
            }
        }
    }

    @Test("property: every item can be reached with the arrow keys")
    func everyItemReachable() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            let shaped = layout([
                (.overlaps, Int.random(in: 0..<4, using: &generator)),
                (.today, Int.random(in: 0..<4, using: &generator)),
                (.mail, Int.random(in: 0..<7, using: &generator)),
            ])
            let count = itemCount(shaped)
            if count == 0 { continue }

            var seen: Set<Int> = [0]
            var queue = [0]
            while let from = queue.first {
                queue.removeFirst()
                for direction in Direction.allCases {
                    let to = move(shaped, from: from, direction)
                    if seen.insert(to).inserted { queue.append(to) }
                }
            }
            #expect(seen.count == count)
        }
    }

    @Test("default keys: arrows move, Escape clears or closes, letters type")
    func defaultKeys() {
        #expect(keyAction("Up") == .move(.up))
        #expect(keyAction("Left") == .move(.left))
        #expect(keyAction("Return") == .open)
        #expect(keyAction("Escape") == .clearOrClose)
        #expect(keyAction("j") == .typing)
        #expect(keyAction("j", preset: keyPreset("unknown preset")) == .typing)
    }

    @Test("vim keys have real modes")
    func vimModes() {
        // Insert mode types into the search; Escape leaves it.
        #expect(keyAction("j", preset: .vim, mode: .insert) == .typing)
        #expect(keyAction("Escape", preset: .vim, mode: .insert) == .normalMode)
        // Normal mode moves with h/j/k/l and swallows other letters.
        #expect(
            ["h", "j", "k", "l"].map { keyAction($0, preset: .vim, mode: .normal) }
                == [.move(.left), .move(.down), .move(.up), .move(.right)]
        )
        #expect(keyAction("x", preset: .vim, mode: .normal) == .ignore)
        #expect(keyAction("i", preset: .vim, mode: .normal) == .insertMode)
        #expect(keyAction("/", preset: .vim, mode: .normal) == .insertMode)
        #expect(keyAction("Escape", preset: .vim, mode: .normal) == .close)
        // Arrows and Enter work in both modes.
        #expect(keyAction("Down", preset: .vim, mode: .insert) == .move(.down))
        #expect(keyAction("Return", preset: .vim, mode: .normal) == .open)
    }

    @Test("Ctrl+R refreshes in every preset and mode")
    func refreshing() {
        let combinations: [(KeyPreset, Mode)] = [(.default, .insert), (.vim, .insert), (.vim, .normal)]
        for (preset, mode) in combinations {
            #expect(keyAction("r", ctrl: true, preset: preset, mode: mode) == .refresh)
        }
        // Other Ctrl chords edit the search in insert mode, and do nothing in normal mode.
        #expect(keyAction("u", ctrl: true, preset: .vim, mode: .insert) == .typing)
        #expect(keyAction("u", ctrl: true, preset: .vim, mode: .normal) == .ignore)
    }

    @Test("Tab and Shift+Tab change the range")
    func rangeKeys() {
        #expect(keyAction("Tab") == .rangeNext)
        #expect(keyAction("Backtab", preset: .vim, mode: .normal) == .rangePrev)
    }

    @Test("a refresh shows it is running, then its result")
    func status() {
        let fetchedAt = moment(day: 18, hour: 13, minute: 20)
        let snapshot = Snapshot(fetchedAt: fetchedAt)

        #expect(statusLine(refreshing: true, snapshot: snapshot, runFailed: false) == .refreshing)
        #expect(statusLine(refreshing: false, snapshot: snapshot, runFailed: false) == .updated(at: fetchedAt))
        #expect(statusLine(refreshing: false, snapshot: snapshot, runFailed: true) == .failed(at: fetchedAt))
        #expect(statusLine(refreshing: false, snapshot: nil, runFailed: false) == .fetching)
    }

    @Test("the key preset falls back to default")
    func presetFallback() {
        #expect(keyPreset("vim") == .vim)
        #expect(keyPreset("emacs") == .default)
        #expect(keyPreset(nil) == .default)
    }

    @Test("gg and G jump to the first and last item in vim normal mode")
    func ggAndG() {
        // A single g waits for the second one, as in vim.
        #expect(keyAction("g", preset: .vim, mode: .normal, previous: "") == .pending)
        #expect(keyAction("g", preset: .vim, mode: .normal, previous: "g") == .jump(.first))
        #expect(keyAction("G", preset: .vim, mode: .normal, previous: "") == .jump(.last))
        #expect(keyAction("G", preset: .vim, mode: .normal, previous: "g") == .jump(.last))
        // Anything else after a g just does its own thing.
        #expect(keyAction("j", preset: .vim, mode: .normal, previous: "g") == .move(.down))
    }

    @Test("g and G type into the search in insert mode and with default keys")
    func ggTypes() {
        #expect(keyAction("g", preset: .vim, mode: .insert, previous: "g") == .typing)
        #expect(keyAction("G", preset: .vim, mode: .insert) == .typing)
        #expect(keyAction("g", preset: .default, mode: .insert, previous: "g") == .typing)
        #expect(keyAction("G", preset: .default) == .typing)
    }

    @Test("first and last are the ends of the whole list, across sections")
    func edges() {
        #expect(edge(threeSections, .first) == 0)
        #expect(edge(threeSections, .last) == 8)
        #expect(edge(layout([]), .last) == 0)
    }

    @Test("vim keys open in normal mode; default keys type straight away")
    func startingMode() {
        #expect(initialMode(.vim) == .normal)
        #expect(initialMode(.default) == .insert)
        #expect(initialMode(keyPreset(nil)) == .insert)
    }
}
