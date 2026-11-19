const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Local wall-clock times; run with TZ set so the day boundaries are fixed.
const now = new Date(2026, 10, 17, 7, 30)

function at(day, hour, minute = 0) {
  return new Date(2026, 10, day, hour, minute).toISOString()
}

function event(id, day, hour, hours = 1, extra = {}) {
  return { id, title: id, calendarName: "Family", start: at(day, hour), end: at(day, hour + hours),
           allDay: false, kind: "none", link: "https://www.icloud.com/calendar/", ...extra }
}

function card(day, hour) {
  return { start: at(day, hour), end: at(day, hour + 1), kind: "same",
           events: [event("a", day, hour - 1, 2), event("b", day, hour, 2)] }
}

const snapshot = {
  events: [event("pickup", 17, 15), event("dentist", 18, 10, 1, { calendarName: "Partner" }), event("trip", 30, 9)],
  overlaps: [card(17, 15), card(20, 9), card(30, 9)],
  mail: [{ subject: "Early pickup Friday", sender: "School office", account: "you@example.com",
           link: "https://mail.google.com/mail/?authuser=gf#all/t1" }],
  errors: []
}

function keys(sections) {
  return sections.map((s) => s.key)
}

test("without a query: overlaps in range, then today, then mail", () => {
  const sections = Model.modalSections(snapshot, now, 7, "")

  assert.deepEqual(keys(sections), ["overlaps", "today", "mail"])
  assert.equal(sections[0].items.length, 2)
  assert.deepEqual(sections[1].items.map((i) => i.value.id), ["pickup"])
})

test("the overlaps section is hidden when there are none in range", () => {
  assert.deepEqual(keys(Model.modalSections({ ...snapshot, overlaps: [] }, now, 7, "")), ["today", "mail"])
})

test("today and mail stay visible when empty, so the view keeps its shape", () => {
  const empty = { events: [], overlaps: [], mail: [], errors: [] }
  assert.deepEqual(keys(Model.modalSections(empty, now, 7, "")), ["today", "mail"])
})

test("a query searches every fetched event and all mail", () => {
  const sections = Model.modalSections(snapshot, now, 0, "PICKUP")

  assert.deepEqual(keys(sections), ["events", "mail"])
  assert.deepEqual(sections[0].items.map((i) => i.value.id), ["pickup"])
  assert.equal(sections[1].items[0].value.subject, "Early pickup Friday")
})

test("a query matches calendar names and senders, and drops empty sections", () => {
  assert.deepEqual(Model.modalSections(snapshot, now, 7, "partner")[0].items.map((i) => i.value.id), ["dentist"])
  assert.deepEqual(keys(Model.modalSections(snapshot, now, 7, "school")), ["mail"])
  assert.deepEqual(Model.modalSections(snapshot, now, 7, "nothing like this"), [])
})

test("items are numbered across sections for keyboard selection", () => {
  const sections = Model.modalSections(snapshot, now, 7, "")

  assert.equal(Model.itemCount(sections), 4)
  assert.deepEqual(sections.flatMap((s) => s.items.map((i) => i.index)), [0, 1, 2, 3])
  assert.equal(Model.itemAt(sections, 3).type, "mail")
  assert.equal(Model.itemAt(sections, 9), null)
})

test("enter opens the item's link; a card opens its first event", () => {
  const sections = Model.modalSections(snapshot, now, 7, "")

  assert.equal(Model.linkOf(Model.itemAt(sections, 0)), "https://www.icloud.com/calendar/")
  assert.equal(Model.linkOf(Model.itemAt(sections, 3)), "https://mail.google.com/mail/?authuser=gf#all/t1")
  assert.equal(Model.linkOf(null), "")
})

test("only links to the services Omaview reads can open", () => {
  for (const ok of ["https://www.google.com/calendar/event?eid=abc",
                    "https://calendar.google.com/calendar/r/day/2026/11/17?authuser=gf%40x.com",
                    "https://mail.google.com/mail/?authuser=gf#all/t1",
                    "https://www.icloud.com/calendar/"]) {
    assert.equal(Model.safeLink(ok), ok)
  }
  for (const bad of ["http://mail.google.com/", "https://mail.google.com.evil.com/", "https://evil.com/?https://mail.google.com/",
                     "javascript:alert(1)", "file:///etc/passwd", "https://www.google.com/search?q=x",
                     "https://mail.google.com/ --flag", "https://mail.google.com/\nx", "", null]) {
    assert.equal(Model.safeLink(bad), "", String(bad))
  }
})

test("timeline spans are fractions of the window, clamped to it", () => {
  const start = new Date(2026, 10, 17, 6)
  const end = new Date(2026, 10, 17, 22)

  assert.deepEqual(Model.timelineSpan(new Date(2026, 10, 17, 14), new Date(2026, 10, 17, 18), start, end), { x: 0.5, width: 0.25 })
  assert.deepEqual(Model.timelineSpan(new Date(2026, 10, 17, 4), new Date(2026, 10, 17, 7), start, end), { x: 0, width: 1 / 16 })
  assert.deepEqual(Model.timelineSpan(start, end, end, start), { x: 0, width: 0 })
})

test("the day strip covers 6 to 22, widened for earlier or later events", () => {
  const hours = (w) => [w.start.getHours(), w.end.getHours() || 24]

  assert.deepEqual(hours(Model.dayWindow([event("x", 17, 9)], now)), [6, 22])
  assert.deepEqual(hours(Model.dayWindow([event("early", 17, 5), event("late", 17, 22, 1, { end: at(17, 23, 30) })], now)), [5, 24])
  assert.deepEqual(hours(Model.dayWindow([event("bday", 17, 0, 24, { allDay: true })], now)), [6, 22])
})

test("a card's timeline spans both of its events", () => {
  const window = Model.cardWindow(card(17, 15))

  assert.equal(window.start.getHours(), 14)
  assert.equal(window.end.getHours(), 17)
})
