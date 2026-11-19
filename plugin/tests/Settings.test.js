// The settings view: reading and saving the widget's shell.json entry
// (specs/Settings.tla), the rows it shows, and its keys.
const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

function random(seed) {
  return () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
}

test("Settings.TypeOK: every setting has a value, with safe defaults", () => {
  assert.deepEqual(Model.readSettings({}), { refreshMinutes: 60, keys: "default", defaultRange: 7 })
  assert.deepEqual(Model.readSettings(null), { refreshMinutes: 60, keys: "default", defaultRange: 7 })
  assert.deepEqual(Model.readSettings({ refreshMinutes: 15, keys: "vim", defaultRange: 3 }),
                   { refreshMinutes: 15, keys: "vim", defaultRange: 3 })
  assert.deepEqual(Model.readSettings({ refreshMinutes: "0" }).refreshMinutes, 0)
  assert.deepEqual(Model.readSettings({ refreshMinutes: -5, keys: "emacs", defaultRange: 5 }),
                   { refreshMinutes: 0, keys: "default", defaultRange: 7 })
})

test("Settings.OtherSettingsSurvive: changing one setting leaves every other setting as it was", () => {
  const next = random(11)
  const keys = ["refreshMinutes", "keys", "defaultRange", "somethingElse"]
  for (let run = 0; run < 500; run++) {
    const entry = {}
    keys.forEach((key) => { if (next() < 0.7) entry[key] = Math.floor(next() * 100) })
    const changed = keys[Math.floor(next() * keys.length)]
    const value = Math.floor(next() * 100)
    const before = JSON.parse(JSON.stringify(entry))

    const after = Model.withSetting(entry, changed, value)

    assert.equal(after[changed], value)
    keys.filter((key) => key !== changed).forEach((key) => assert.deepEqual(after[key], before[key], key))
    assert.deepEqual(entry, before, "the current entry is not modified in place")
  }
})

test("withSetting never carries the widget id into the settings", () => {
  assert.deepEqual(Model.withSetting({ id: "georgef.omaview", keys: "vim" }, "defaultRange", 3), { keys: "vim", defaultRange: 3 })
})

test("values cycle through their options and wrap", () => {
  assert.equal(Model.cycle([0, 15, 30, 60, 120], 60, 1), 120)
  assert.equal(Model.cycle([0, 15, 30, 60, 120], 120, 1), 0)
  assert.equal(Model.cycle([0, 15, 30, 60, 120], 0, -1), 120)
  assert.equal(Model.cycle(["off", "personal", "work"], "unknown", 1), "off")
})

const listing = [
  { provider: "google", account: "gf@x.com", mail: true, error: "",
    calendars: [{ id: "gf@x.com", name: "Mine", tag: "personal" }, { id: "holidays", name: "Holidays", tag: "off" }] },
  { provider: "icloud", account: "me@icloud.com", mail: false, error: "",
    calendars: [{ id: "/1/home/", name: "George", tag: "personal" }] }
]

test("settings rows: the three general settings, then every calendar", () => {
  const rows = Model.settingsRows({ refreshMinutes: 30, keys: "vim" }, listing)

  assert.deepEqual(rows.map((r) => [r.kind, r.key || r.id, r.value]), [
    ["setting", "refreshMinutes", 30],
    ["setting", "keys", "vim"],
    ["setting", "defaultRange", 7],
    ["calendar", "gf@x.com", "personal"],
    ["calendar", "holidays", "off"],
    ["calendar", "/1/home/", "personal"]
  ])
  assert.deepEqual(rows[0].options, [0, 15, 30, 60, 120])
  assert.deepEqual(rows[1].options, ["default", "vim"])
  assert.deepEqual(rows[2].options, [0, 1, 3, 7, 14])
  assert.deepEqual(rows[3].options, ["off", "personal", "work"])
  assert.deepEqual([rows[5].provider, rows[5].account, rows[5].name], ["icloud", "me@icloud.com", "George"])
  assert.deepEqual(rows.map((r) => r.index), [0, 1, 2, 3, 4, 5])
})

test("settings rows: only the general settings while calendars are loading", () => {
  assert.equal(Model.settingsRows({}, null).length, 3)
})

test("settings keys: arrows in both presets, h/j/k/l only with vim", () => {
  for (const preset of ["default", "vim"]) {
    assert.equal(Model.settingsKeyAction("Up", false, preset), "up")
    assert.equal(Model.settingsKeyAction("Down", false, preset), "down")
    assert.equal(Model.settingsKeyAction("Left", false, preset), "previous")
    assert.equal(Model.settingsKeyAction("Right", false, preset), "next")
    assert.equal(Model.settingsKeyAction("Return", false, preset), "next")
    assert.equal(Model.settingsKeyAction("Escape", false, preset), "back")
    assert.equal(Model.settingsKeyAction(",", true, preset), "back")
  }
  assert.deepEqual(["h", "j", "k", "l"].map((k) => Model.settingsKeyAction(k, false, "vim")), ["previous", "down", "up", "next"])
  assert.equal(Model.settingsKeyAction("j", false, "default"), "ignore")
  assert.equal(Model.settingsKeyAction("x", false, "vim"), "ignore")
})

test("Ctrl+, opens settings from the main view, in every preset and mode", () => {
  for (const [preset, mode] of [["default", "insert"], ["vim", "insert"], ["vim", "normal"]]) {
    assert.equal(Model.keyAction(",", true, preset, mode), "settings")
  }
})

test("the calendar listing from `omaview calendars --json` is validated and bounded", () => {
  assert.equal(Model.parseListing(""), null)
  assert.equal(Model.parseListing("{}"), null)
  assert.deepEqual(Model.parseListing("[]"), [])

  const parsed = Model.parseListing(JSON.stringify([
    { provider: "icloud", account: "me@icloud.com", mail: false, error: "", calendars: Array(300).fill({ id: "x", name: "X", tag: "personal" }) },
    { provider: "google", account: "broken" }
  ]))
  assert.equal(parsed.length, 1)
  assert.equal(parsed[0].calendars.length, 100)
})

test("found: a calendar can go Off → Personal → Work from the keyboard", () => {
  // Each key press changes the shown value at once, so the next one cycles from it.
  let current = listing
  const id = "holidays"
  const seen = []
  for (let press = 0; press < 3; press++) {
    const row = Model.settingsRows({}, current).find((r) => r.id === id)
    const choice = Model.cycle(row.options, row.value, 1)
    current = Model.withTag(current, row, choice)
    seen.push(Model.settingsRows({}, current).find((r) => r.id === id).value)
  }
  assert.deepEqual(seen, ["personal", "work", "off"])
})

test("withTag changes only that calendar, and leaves the listing it was given alone", () => {
  const before = JSON.parse(JSON.stringify(listing))
  const row = Model.settingsRows({}, listing).find((r) => r.id === "/1/home/")

  const after = Model.withTag(listing, row, "work")

  assert.deepEqual(after[1].calendars, [{ id: "/1/home/", name: "George", tag: "work" }])
  assert.deepEqual(after[0], before[0])
  assert.deepEqual(listing, before)
  assert.equal(Model.withTag(null, row, "work"), null)
})

test("found: gg and G jump to the first and last setting with vim keys", () => {
  assert.equal(Model.settingsKeyAction("g", false, "vim", ""), "pending")
  assert.equal(Model.settingsKeyAction("g", false, "vim", "g"), "first")
  assert.equal(Model.settingsKeyAction("G", false, "vim", ""), "last")
  assert.equal(Model.settingsKeyAction("G", false, "default", ""), "ignore")
  assert.equal(Model.settingsKeyAction("g", false, "default", "g"), "ignore")
})
