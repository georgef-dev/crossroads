// Keyboard behavior of the modal: moving the selection, the two key presets,
// cycling the range, and refresh feedback.
const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Sections shaped like Model.modalSections output.
function sections(...shapes) {
  let index = 0
  return shapes.map(([key, count]) => ({
    key,
    columns: key === "mail" ? 2 : 1,
    items: Array.from({ length: count }, () => ({ index: index++ }))
  }))
}

function press(layout, start, ...directions) {
  return directions.reduce((index, direction) => Model.move(layout, index, direction), start)
}

// Indices: overlaps 0-1, today 2-3, mail 4-8 (rows: 4 5 / 6 7 / 8).
const layout = sections(["overlaps", 2], ["today", 2], ["mail", 5])

test("modal sections: mail is a two-column grid, everything else a list", () => {
  const built = Model.modalSections({ events: [], overlaps: [], mail: [{}, {}], errors: [] }, new Date(), 7, "")
  assert.deepEqual(built.map((s) => [s.key, s.columns]), [["today", 1], ["mail", 2]])
})

test("found: left and right move between the mail columns", () => {
  assert.equal(press(layout, 4, "right"), 5)
  assert.equal(press(layout, 5, "left"), 4)
  assert.equal(press(layout, 7, "left"), 6)
})

test("left and right stop at the edges of a row and never leave the grid", () => {
  assert.equal(press(layout, 4, "left"), 4)
  assert.equal(press(layout, 5, "right"), 5)
  assert.equal(press(layout, 8, "right"), 8)
})

test("left and right do nothing in single-column lists", () => {
  assert.equal(press(layout, 2, "left"), 2)
  assert.equal(press(layout, 2, "right"), 2)
})

test("up and down move through lists and across sections", () => {
  assert.equal(press(layout, 0, "down", "down", "down"), 3)
  assert.equal(press(layout, 3, "down"), 4)
  assert.equal(press(layout, 4, "up"), 3)
  assert.equal(press(layout, 0, "up"), 0)
})

test("up and down move by whole rows in the mail grid", () => {
  assert.equal(press(layout, 5, "down"), 7)
  assert.equal(press(layout, 7, "up"), 5)
  assert.equal(press(layout, 5, "up"), 3)
  // The last row is short: moving down from its column lands on its last card.
  assert.equal(press(layout, 7, "down"), 8)
  assert.equal(press(layout, 8, "down"), 8)
})

test("empty sections are skipped", () => {
  const withEmpty = sections(["today", 1], ["events", 0], ["mail", 2])
  assert.equal(press(withEmpty, 0, "down"), 1)
  assert.equal(press(withEmpty, 1, "up"), 0)
})

// A small deterministic generator, so failures reproduce.
function random(seed) {
  return () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
}

test("property: the selection is always on a real item, whatever keys are pressed", () => {
  const next = random(42)
  const keys = ["MAIL", "overlaps", "today", "events"]
  for (let run = 0; run < 300; run++) {
    const shapes = keys.map((key) => [key === "MAIL" ? "mail" : key, Math.floor(next() * 6)])
    const shaped = sections(...shapes)
    const count = Model.itemCount(shaped)
    let index = 0
    for (let step = 0; step < 40; step++) {
      index = Model.move(shaped, index, ["up", "down", "left", "right"][Math.floor(next() * 4)])
      if (count > 0) assert.ok(index >= 0 && index < count, `index ${index} of ${count}`)
    }
  }
})

test("property: every item can be reached with the arrow keys", () => {
  const next = random(7)
  for (let run = 0; run < 200; run++) {
    const shaped = sections(["overlaps", Math.floor(next() * 4)], ["today", Math.floor(next() * 4)], ["mail", Math.floor(next() * 7)])
    const count = Model.itemCount(shaped)
    if (count === 0) continue
    const seen = new Set([0])
    const queue = [0]
    while (queue.length) {
      const from = queue.shift()
      for (const direction of ["up", "down", "left", "right"]) {
        const to = Model.move(shaped, from, direction)
        if (!seen.has(to)) { seen.add(to); queue.push(to) }
      }
    }
    assert.equal(seen.size, count)
  }
})

test("default keys: arrows move, Escape clears or closes, letters type", () => {
  assert.equal(Model.keyAction("Up", false, "default", "insert"), "up")
  assert.equal(Model.keyAction("Left", false, "default", "insert"), "left")
  assert.equal(Model.keyAction("Return", false, "default", "insert"), "open")
  assert.equal(Model.keyAction("Escape", false, "default", "insert"), "clearOrClose")
  assert.equal(Model.keyAction("j", false, "default", "insert"), "")
  assert.equal(Model.keyAction("j", false, "unknown preset", "insert"), "")
})

test("found: vim keys have real modes", () => {
  // Insert mode types into the search; Escape leaves it.
  assert.equal(Model.keyAction("j", false, "vim", "insert"), "")
  assert.equal(Model.keyAction("Escape", false, "vim", "insert"), "normalMode")
  // Normal mode moves with h/j/k/l and swallows other letters.
  assert.deepEqual(["h", "j", "k", "l"].map((k) => Model.keyAction(k, false, "vim", "normal")), ["left", "down", "up", "right"])
  assert.equal(Model.keyAction("x", false, "vim", "normal"), "ignore")
  assert.equal(Model.keyAction("i", false, "vim", "normal"), "insertMode")
  assert.equal(Model.keyAction("/", false, "vim", "normal"), "insertMode")
  assert.equal(Model.keyAction("Escape", false, "vim", "normal"), "close")
  // Arrows and Enter work in both modes.
  assert.equal(Model.keyAction("Down", false, "vim", "insert"), "down")
  assert.equal(Model.keyAction("Return", false, "vim", "normal"), "open")
})

test("found: Ctrl+R refreshes in every preset and mode", () => {
  for (const [preset, mode] of [["default", "insert"], ["vim", "insert"], ["vim", "normal"]]) {
    assert.equal(Model.keyAction("r", true, preset, mode), "refresh")
  }
  // Other Ctrl chords edit the search in insert mode, and do nothing in normal mode.
  assert.equal(Model.keyAction("u", true, "vim", "insert"), "")
  assert.equal(Model.keyAction("u", true, "vim", "normal"), "ignore")
})

test("found: Tab and Shift+Tab change the range, wrapping around", () => {
  assert.equal(Model.keyAction("Tab", false, "default", "insert"), "rangeNext")
  assert.equal(Model.keyAction("Backtab", false, "vim", "normal"), "rangePrev")

  const visited = [0]
  for (let i = 0; i < 5; i++) visited.push(Model.nextRange(visited[visited.length - 1], 1, true))
  assert.deepEqual(visited, [0, 1, 3, 7, 14, 0])
  assert.equal(Model.nextRange(0, -1, true), 14)
})

test("found: a refresh shows it is running, then its result", () => {
  const snapshot = { fetchedAt: "2026-11-18T13:20:00-05:00" }
  assert.deepEqual(Model.statusLine(true, snapshot, false), { kind: "refreshing", time: "" })
  assert.deepEqual(Model.statusLine(false, snapshot, false), { kind: "updated", time: snapshot.fetchedAt })
  assert.deepEqual(Model.statusLine(false, snapshot, true), { kind: "failed", time: snapshot.fetchedAt })
  assert.deepEqual(Model.statusLine(false, null, false), { kind: "fetching", time: "" })
})

test("the key preset falls back to default", () => {
  assert.equal(Model.keyPreset("vim"), "vim")
  assert.equal(Model.keyPreset("emacs"), "default")
  assert.equal(Model.keyPreset(undefined), "default")
})

test("found: gg and G jump to the first and last item in vim normal mode", () => {
  // A single g waits for the second one, as in vim.
  assert.equal(Model.keyAction("g", false, "vim", "normal", ""), "pending")
  assert.equal(Model.keyAction("g", false, "vim", "normal", "g"), "first")
  assert.equal(Model.keyAction("G", false, "vim", "normal", ""), "last")
  assert.equal(Model.keyAction("G", false, "vim", "normal", "g"), "last")
  // Anything else after a g just does its own thing.
  assert.equal(Model.keyAction("j", false, "vim", "normal", "g"), "down")
})

test("g and G type into the search in insert mode and with default keys", () => {
  assert.equal(Model.keyAction("g", false, "vim", "insert", "g"), "")
  assert.equal(Model.keyAction("G", false, "vim", "insert", ""), "")
  assert.equal(Model.keyAction("g", false, "default", "insert", "g"), "")
  assert.equal(Model.keyAction("G", false, "default", "insert", ""), "")
})

test("first and last are the ends of the whole list, across sections", () => {
  assert.equal(Model.edge(layout, "first"), 0)
  assert.equal(Model.edge(layout, "last"), 8)
  assert.equal(Model.edge(sections(), "last"), 0)
})

test("vim keys open in normal mode; default keys type straight away", () => {
  assert.equal(Model.initialMode("vim"), "normal")
  assert.equal(Model.initialMode("default"), "insert")
  assert.equal(Model.initialMode(undefined), "insert")
})
