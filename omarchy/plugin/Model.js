// Pure range, grouping and color math for the Crossroads panel. The snapshot
// comes from `crossroads fetch`, which already computed each event's kind.

var RANGES = [0, 1, 3, 7, 14]
var DEFAULT_RANGE = 7
var MAX_EVENTS = 500
var MAX_MAIL = 50

// Untrusted command output: accept only the expected shape, within bounds.
function parseSnapshot(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!parsed || !Array.isArray(parsed.events) || !Array.isArray(parsed.mail) || !Array.isArray(parsed.errors)) return null
  return {
    fetchedAt: String(parsed.fetchedAt || ""),
    events: parsed.events.slice(0, MAX_EVENTS),
    overlaps: Array.isArray(parsed.overlaps) ? parsed.overlaps.slice(0, MAX_EVENTS) : [],
    mail: parsed.mail.slice(0, MAX_MAIL),
    errors: parsed.errors.slice(0, MAX_MAIL)
  }
}

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

// Today plus `days` more days, in local time.
function eventsInRange(snapshot, now, days) {
  var from = startOfDay(now)
  var until = addDays(from, days + 1)
  return (snapshot ? snapshot.events : []).filter(function(event) {
    return new Date(event.start) < until && new Date(event.end) > from
  })
}

// Events grouped under the day they start, or today if they started earlier.
function groupByDay(events, now) {
  var today = startOfDay(now)
  var days = []
  events.forEach(function(event) {
    var day = startOfDay(new Date(event.start))
    if (day < today) day = today
    var last = days[days.length - 1]
    if (last && last.day.getTime() === day.getTime()) last.events.push(event)
    else days.push({ day: day, events: [event] })
  })
  return days
}

function flaggedCount(events) {
  return events.filter(function(event) { return event.kind !== "none" }).length
}

// How an event is colored: its tag's color, a darker shade of it when it
// overlaps its own tag, or a blend of both tags when personal meets work.
function shade(event) {
  if (event.kind === "mixed") return "blend"
  if (event.kind === "same") return "darker"
  return "plain"
}

// Theme colors for an event or card. These use Qt's color helpers, so they
// run only inside the shell, not under node.
function tagColor(tag, personal, work) {
  return tag === "work" ? work : personal
}

function eventColor(event, personal, work) {
  var kind = shade(event)
  if (kind === "blend")
    return Qt.rgba((personal.r + work.r) / 2, (personal.g + work.g) / 2, (personal.b + work.b) / 2, 1)
  if (kind === "darker") return Qt.darker(tagColor(event.tag, personal, work), 1.6)
  return tagColor(event.tag, personal, work)
}

// A card's color follows its kind and its first event's tag.
function cardColor(card, personal, work) {
  return eventColor({ kind: card.kind, tag: card.events[0].tag }, personal, work)
}

// Arrows in the panel stop at the ends; Tab in the modal wraps around.
function nextRange(days, step, wrap) {
  var index = RANGES.indexOf(days)
  if (index < 0) index = RANGES.indexOf(DEFAULT_RANGE)
  if (wrap) return RANGES[(index + step + RANGES.length) % RANGES.length]
  return RANGES[Math.max(0, Math.min(RANGES.length - 1, index + step))]
}

// ---- Modal.

function matches(query, values) {
  return values.some(function(value) { return String(value || "").toLowerCase().indexOf(query) !== -1 })
}

// What the modal lists, in order. Every item carries its position in the
// whole list, so keyboard selection can move across sections.
function modalSections(snapshot, now, days, query) {
  var q = String(query || "").trim().toLowerCase()
  var sections
  if (q) {
    sections = [
      { key: "events", type: "event", values: (snapshot ? snapshot.events : []).filter(function(e) {
        return matches(q, [e.title, e.calendarName])
      }) },
      { key: "mail", type: "mail", values: (snapshot ? snapshot.mail : []).filter(function(m) {
        return matches(q, [m.subject, m.sender, m.account])
      }) }
    ].filter(function(section) { return section.values.length > 0 })
  } else {
    sections = [
      { key: "overlaps", type: "card", values: eventsInRange(snapshot ? { events: snapshot.overlaps } : null, now, days) },
      { key: "today", type: "event", values: eventsInRange(snapshot, now, 0) },
      { key: "mail", type: "mail", values: snapshot ? snapshot.mail : [] }
    ].filter(function(section) { return section.key !== "overlaps" || section.values.length > 0 })
  }

  var index = 0
  return sections.map(function(section) {
    return {
      key: section.key,
      // Mail shows as a grid of two cards per row; everything else is a list.
      columns: section.key === "mail" ? MAIL_COLUMNS : 1,
      items: section.values.map(function(value) {
        return { type: section.type, value: value, index: index++ }
      })
    }
  })
}

// ---- Keyboard.

var MAIL_COLUMNS = 2
var KEY_PRESETS = ["default", "vim"]

function keyPreset(value) {
  return KEY_PRESETS.indexOf(value) !== -1 ? value : "default"
}

// Vim keys open in normal mode, ready to move; default keys open ready to search.
function initialMode(preset) {
  return keyPreset(preset) === "vim" ? "normal" : "insert"
}

// What a key press does, or "" when the modal should treat it as typing.
// `key` is a name ("Up", "Escape", "Tab", "Backtab", "Return", ...) or the
// character typed. Vim mode has two modes: insert types into the search,
// normal moves with h/j/k/l, gg and G. `previous` is the key before, for gg.
function keyAction(key, ctrl, preset, mode, previous) {
  var normalMode = keyPreset(preset) === "vim" && mode === "normal"
  if (ctrl && key === ",") return "settings"
  if (ctrl) return key === "r" || key === "R" ? "refresh" : (normalMode ? "ignore" : "")
  var arrows = { Up: "up", Down: "down", Left: "left", Right: "right" }
  if (arrows[key]) return arrows[key]
  if (key === "Tab") return "rangeNext"
  if (key === "Backtab") return "rangePrev"
  if (key === "Return") return "open"

  if (keyPreset(preset) !== "vim") return key === "Escape" ? "clearOrClose" : ""
  if (mode === "insert") return key === "Escape" ? "normalMode" : ""
  var normal = { h: "left", j: "down", k: "up", l: "right", G: "last", i: "insertMode", "/": "insertMode", Escape: "close" }
  if (key === "g") return previous === "g" ? "first" : "pending"
  // Other keys do nothing in normal mode rather than typing into the search.
  return normal[key] || "ignore"
}

// The first or last item of the whole list, for gg and G.
function edge(sections, which) {
  return which === "last" ? Math.max(0, itemCount(sections) - 1) : 0
}

function locate(sections, index) {
  for (var s = 0; s < sections.length; s++) {
    for (var p = 0; p < sections[s].items.length; p++) {
      if (sections[s].items[p].index === index) return { section: s, position: p }
    }
  }
  return null
}

// The selection after moving one step, across sections and within grids.
// Moves that lead nowhere keep the current selection.
function move(sections, index, direction) {
  var at = locate(sections, index)
  if (!at) return itemCount(sections) > 0 ? 0 : index
  var section = sections[at.section]
  var items = section.items
  var columns = section.columns || 1
  var p = at.position
  var row = Math.floor(p / columns)
  var lastRow = Math.floor((items.length - 1) / columns)

  if (direction === "left") return p % columns > 0 ? items[p - 1].index : index
  if (direction === "right") return p % columns < columns - 1 && p + 1 < items.length ? items[p + 1].index : index
  if (direction === "down") {
    if (row < lastRow) return items[Math.min(p + columns, items.length - 1)].index
    var next = sections.slice(at.section + 1).filter(function(s) { return s.items.length > 0 })[0]
    return next ? next.items[0].index : index
  }
  if (direction === "up") {
    if (row > 0) return items[p - columns].index
    var previous = sections.slice(0, at.section).filter(function(s) { return s.items.length > 0 }).pop()
    return previous ? previous.items[previous.items.length - 1].index : index
  }
  return index
}

// What the footer says about freshness.
function statusLine(refreshing, snapshot, runFailed) {
  if (refreshing) return { kind: "refreshing", time: "" }
  if (runFailed) return { kind: "failed", time: snapshot ? snapshot.fetchedAt : "" }
  if (snapshot) return { kind: "updated", time: snapshot.fetchedAt }
  return { kind: "fetching", time: "" }
}

// ---- Settings (specs/Settings.tla).

var REFRESH_OPTIONS = [0, 15, 30, 60, 120]
var TAG_OPTIONS = ["off", "personal", "work"]

// The widget's shell.json entry as settings, each with a safe default.
function readSettings(entry) {
  var e = entry || {}
  var refresh = parseInt(e.refreshMinutes, 10)
  var range = parseInt(e.defaultRange, 10)
  return {
    refreshMinutes: isNaN(refresh) ? 60 : Math.max(0, refresh),
    keys: keyPreset(e.keys),
    defaultRange: RANGES.indexOf(range) !== -1 ? range : DEFAULT_RANGE
  }
}

// The shell replaces the whole entry on save, so the new entry is the old
// one with one value changed. The widget id is never part of the settings.
function withSetting(entry, key, value) {
  var next = {}
  for (var name in (entry || {})) if (name !== "id") next[name] = entry[name]
  next[key] = value
  return next
}

function cycle(options, value, step) {
  var index = options.indexOf(value)
  if (index < 0) return options[0]
  return options[(index + step + options.length) % options.length]
}

// ---- Shortcut (specs/Settings.tla). Written like Hyprland: "SUPER + ALT + C".

var DEFAULT_SHORTCUT = "SUPER + ALT + C"
var SHORTCUT_MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"]

// The shortcut a key press makes, or "" while it isn't one yet. `keyName` is
// "A"-"Z", "0"-"9", "F1"-"F12" or "SPACE"; anything else, like a modifier on
// its own, isn't a shortcut.
function shortcutFromKey(modifiers, keyName) {
  var key = String(keyName || "")
  var allowed = /^([A-Z0-9]|F([1-9]|1[0-2])|SPACE)$/.test(key)
  if (!allowed || !(modifiers.super || modifiers.ctrl || modifiers.alt)) return ""
  var parts = SHORTCUT_MODIFIERS.filter(function(m) { return modifiers[m.toLowerCase()] })
  return parts.concat([key]).join(" + ")
}

// "SUPER + ALT + C" as people write it: "Super+Alt+C".
function shortcutLabel(combo) {
  return String(combo || "").split(" + ").map(function(part) {
    return part.length > 1 && !/^F\d+$/.test(part) ? part.charAt(0) + part.slice(1).toLowerCase() : part
  }).join("+")
}

// What the settings view lists: the general settings, the shortcut, then
// every calendar the configured accounts can see. `listing` is null while it loads.
function settingsRows(entry, listing, shortcut) {
  var settings = readSettings(entry)
  var rows = [
    { kind: "setting", key: "refreshMinutes", options: REFRESH_OPTIONS, value: settings.refreshMinutes },
    { kind: "setting", key: "keys", options: KEY_PRESETS, value: settings.keys },
    { kind: "setting", key: "defaultRange", options: RANGES, value: settings.defaultRange },
    { kind: "shortcut", key: "shortcut", options: [], value: shortcut || DEFAULT_SHORTCUT }
  ]
  ;(listing || []).forEach(function(account) {
    account.calendars.forEach(function(calendar) {
      rows.push({ kind: "calendar", provider: account.provider, account: account.account,
                  id: calendar.id, name: calendar.name, options: TAG_OPTIONS, value: calendar.tag })
    })
  })
  rows.forEach(function(row, index) { row.index = index })
  return rows
}

// The listing with one calendar's tag changed, shown before `crossroads tag`
// finishes so the next key press cycles from what the user sees.
function withTag(listing, row, choice) {
  if (!listing) return listing
  return listing.map(function(account) {
    if (account.provider !== row.provider || account.account !== row.account) return account
    var copy = {}
    for (var key in account) copy[key] = account[key]
    copy.calendars = account.calendars.map(function(calendar) {
      if (calendar.id !== row.id) return calendar
      return { id: calendar.id, name: calendar.name, tag: choice }
    })
    return copy
  })
}

// Untrusted command output, like parseSnapshot: only well-formed accounts, bounded.
function parseListing(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  return parsed.filter(function(account) {
    return account && typeof account.account === "string" && Array.isArray(account.calendars)
  }).slice(0, 20).map(function(account) {
    return {
      provider: String(account.provider || ""),
      account: account.account,
      mail: account.mail === true,
      error: String(account.error || ""),
      calendars: account.calendars.slice(0, 100).map(function(c) {
        return { id: String(c.id || ""), name: String(c.name || c.id || ""), tag: TAG_OPTIONS.indexOf(c.tag) !== -1 ? c.tag : "off" }
      })
    }
  })
}

// Settings has nothing to type into, so letters only move with the vim preset.
function settingsKeyAction(key, ctrl, preset, previous) {
  if (ctrl) return key === "," ? "back" : "ignore"
  var keys = { Up: "up", Down: "down", Left: "previous", Right: "next", Return: "next", Escape: "back", Backspace: "reset" }
  if (keys[key]) return keys[key]
  if (keyPreset(preset) !== "vim") return "ignore"
  if (key === "g") return previous === "g" ? "first" : "pending"
  var vim = { h: "previous", j: "down", k: "up", l: "next", G: "last" }
  return vim[key] || "ignore"
}

function itemCount(sections) {
  return sections.reduce(function(total, section) { return total + section.items.length }, 0)
}

function itemAt(sections, index) {
  for (var i = 0; i < sections.length; i++) {
    for (var j = 0; j < sections[i].items.length; j++) {
      if (sections[i].items[j].index === index) return sections[i].items[j]
    }
  }
  return null
}

// Where an item opens. A card opens its first event.
function linkOf(item) {
  if (!item) return ""
  var link = item.type === "card" ? item.value.events[0].link : item.value.link
  return safeLink(link)
}

// Links come from command output, so only open the services Crossroads reads.
var SAFE_LINK = /^https:\/\/(www\.google\.com\/calendar\/|calendar\.google\.com\/|mail\.google\.com\/|www\.icloud\.com\/calendar\/)[^\s\u0000-\u001f\u007f]*$/

function safeLink(link) {
  var value = String(link || "")
  return SAFE_LINK.test(value) ? value : ""
}

// Position of [start, end) along a timeline window, as fractions of its width.
function timelineSpan(start, end, windowStart, windowEnd) {
  var from = new Date(windowStart).getTime()
  var length = new Date(windowEnd).getTime() - from
  if (length <= 0) return { x: 0, width: 0 }
  var x = Math.max(0, Math.min(1, (new Date(start).getTime() - from) / length))
  var right = Math.max(0, Math.min(1, (new Date(end).getTime() - from) / length))
  return { x: x, width: Math.max(0, right - x) }
}

// The day strip covers 6:00 to 22:00, widened to whole hours that fit
// earlier or later timed events.
function dayWindow(events, now) {
  var day = startOfDay(now)
  var first = 6
  var last = 22
  events.forEach(function(event) {
    if (event.allDay) return
    var start = new Date(event.start)
    var end = new Date(event.end)
    if (start >= day) first = Math.min(first, start.getHours())
    if (end <= addDays(day, 1)) last = Math.max(last, end.getHours() + (end.getMinutes() > 0 ? 1 : 0))
    else last = 24
    if (start < day) first = 0
  })
  return { start: new Date(day.getTime() + first * 3600000), end: new Date(day.getTime() + last * 3600000) }
}

// A card's timeline spans both events, with the overlap inside it.
function cardWindow(card) {
  var starts = card.events.map(function(e) { return new Date(e.start).getTime() })
  var ends = card.events.map(function(e) { return new Date(e.end).getTime() })
  return { start: new Date(Math.min.apply(null, starts)), end: new Date(Math.max.apply(null, ends)) }
}

if (typeof module !== "undefined") module.exports = {
  RANGES: RANGES,
  DEFAULT_RANGE: DEFAULT_RANGE,
  parseSnapshot: parseSnapshot,
  eventsInRange: eventsInRange,
  groupByDay: groupByDay,
  flaggedCount: flaggedCount,
  shade: shade,
  nextRange: nextRange,
  modalSections: modalSections,
  keyPreset: keyPreset,
  initialMode: initialMode,
  DEFAULT_SHORTCUT: DEFAULT_SHORTCUT,
  shortcutFromKey: shortcutFromKey,
  shortcutLabel: shortcutLabel,
  keyAction: keyAction,
  move: move,
  edge: edge,
  statusLine: statusLine,
  readSettings: readSettings,
  withSetting: withSetting,
  cycle: cycle,
  settingsRows: settingsRows,
  parseListing: parseListing,
  withTag: withTag,
  settingsKeyAction: settingsKeyAction,
  itemCount: itemCount,
  itemAt: itemAt,
  linkOf: linkOf,
  safeLink: safeLink,
  timelineSpan: timelineSpan,
  dayWindow: dayWindow,
  cardWindow: cardWindow
}
