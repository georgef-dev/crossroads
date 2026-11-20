const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Local wall-clock times; run with TZ set so the day boundaries are fixed.
const now = new Date(2026, 10, 17, 7, 30)

function at(day, hour, minute = 0) {
  return new Date(2026, 10, day, hour, minute).toISOString()
}

function event(id, day, hour, hours = 1, kind = "none", extra = {}) {
  return { id, start: at(day, hour), end: at(day, hour + hours), kind, tag: "personal", ...extra }
}

const snapshot = {
  events: [
    event("overnight", 16, 22, 4),
    event("today", 17, 9),
    event("tomorrow", 18, 9),
    event("in-three", 20, 9),
    event("in-seven", 24, 9),
    event("in-eight", 25, 9),
    event("in-fourteen", 31, 9)
  ]
}

function ids(events) {
  return events.map((e) => e.id)
}

test("range today shows only today, including events still running from yesterday", () => {
  assert.deepEqual(ids(Model.eventsInRange(snapshot, now, 0)), ["overnight", "today"])
})

test("range today + N includes the Nth day and stops after it", () => {
  assert.deepEqual(ids(Model.eventsInRange(snapshot, now, 1)), ["overnight", "today", "tomorrow"])
  assert.deepEqual(ids(Model.eventsInRange(snapshot, now, 3)), ["overnight", "today", "tomorrow", "in-three"])
  assert.deepEqual(ids(Model.eventsInRange(snapshot, now, 7)).at(-1), "in-seven")
  assert.deepEqual(ids(Model.eventsInRange(snapshot, now, 14)).at(-1), "in-fourteen")
})

test("ranges are today, +1, +3, +7, +14, defaulting to +7", () => {
  assert.deepEqual(Model.RANGES, [0, 1, 3, 7, 14])
  assert.equal(Model.DEFAULT_RANGE, 7)
  assert.equal(Model.nextRange(7, 1), 14)
  assert.equal(Model.nextRange(14, 1), 14)
  assert.equal(Model.nextRange(0, -1), 0)
  assert.equal(Model.nextRange(3, -1), 1)
})

test("all-day events cover their local day", () => {
  const allDay = { id: "bday", start: new Date(2026, 10, 18).toISOString(), end: new Date(2026, 10, 19).toISOString(), kind: "none" }
  assert.deepEqual(ids(Model.eventsInRange({ events: [allDay] }, now, 0)), [])
  assert.deepEqual(ids(Model.eventsInRange({ events: [allDay] }, now, 1)), ["bday"])
})

test("events group by start day, earlier starts under today", () => {
  const days = Model.groupByDay(Model.eventsInRange(snapshot, now, 1), now)

  assert.deepEqual(days.map((d) => d.day.getDate()), [17, 18])
  assert.deepEqual(days.map((d) => ids(d.events)), [["overnight", "today"], ["tomorrow"]])
})

test("the bar counts flagged events", () => {
  const events = [event("a", 17, 9, 1, "mixed"), event("b", 17, 9, 1, "same"), event("c", 17, 12)]
  assert.equal(Model.flaggedCount(events), 2)
})

test("color follows the kind", () => {
  assert.equal(Model.shade({ kind: "none" }), "plain")
  assert.equal(Model.shade({ kind: "same" }), "darker")
  assert.equal(Model.shade({ kind: "mixed" }), "blend")
})

test("snapshots are validated and bounded", () => {
  assert.equal(Model.parseSnapshot(""), null)
  assert.equal(Model.parseSnapshot("not json"), null)
  assert.equal(Model.parseSnapshot('{"events": []}'), null)

  const big = { fetchedAt: "t", events: Array(600).fill({}), mail: Array(80).fill({}), errors: [] }
  const parsed = Model.parseSnapshot(JSON.stringify(big))
  assert.equal(parsed.events.length, 500)
  assert.equal(parsed.mail.length, 50)
})
