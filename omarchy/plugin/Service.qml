import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// One shared data store: fetches on a timer and holds the last good snapshot,
// so the bar widget on every monitor and the modal read the same data and
// each refresh runs `crossroads fetch` once. It also saves settings.
Item {
  id: root

  property var shell: null

  readonly property string pluginId: "georgef.crossroads"
  readonly property string crossroadsPath: Quickshell.env("HOME") + "/.local/share/crossroads/venv/bin/crossroads"

  // The widget's shell.json entry, set by the bar widget. Saving replaces it whole.
  property var entry: ({})
  readonly property var settings: Model.readSettings(entry)
  readonly property int refreshMinutes: settings.refreshMinutes
  readonly property string keys: settings.keys

  // Kept when a fetch fails, so the last good view stays visible.
  property var snapshot: null
  property bool runFailed: false
  readonly property bool refreshing: fetchProc.running

  // Calendars the configured accounts can see, for the settings view; null while loading.
  property var listing: null
  property string tagError: ""
  // Tag changes waiting to be written, oldest first. One write runs at a time.
  property var tagQueue: []

  // The Hyprland shortcut from crossroads.lua; "" until it's read.
  property string shortcut: ""
  property string shortcutError: ""
  readonly property bool shortcutSaving: shortcutProc.running
  readonly property bool tagging: tagProc.running || tagQueue.length > 0

  function refresh() {
    if (!fetchProc.running) fetchProc.running = true
  }

  function toggleModal() {
    if (root.shell) root.shell.toggle(root.pluginId)
  }

  // Shown at once; the shell then writes shell.json and hands back the same entry.
  function saveSetting(key, value) {
    var next = Model.withSetting(root.entry, key, value)
    root.entry = next
    if (root.shell) root.shell.updateEntryInline(root.pluginId, next)
  }

  function loadCalendars() {
    if (!calendarsProc.running) calendarsProc.running = true
  }

  // Shown at once, then written in order. Values go to crossroads as separate
  // arguments, never through a shell.
  function setTag(row, choice) {
    root.tagError = ""
    root.listing = Model.withTag(root.listing, row, choice)
    root.tagQueue = root.tagQueue.concat([[root.crossroadsPath, "tag", row.provider, row.account, row.id, choice, "--name", row.name]])
    root.writeNextTag()
  }

  function loadShortcut() {
    root.runShortcut([root.crossroadsPath, "shortcut"])
  }

  // "reset" brings back the default. The combination goes as its own argument.
  function setShortcut(combo) {
    root.shortcutError = ""
    root.runShortcut(combo === "reset" ? [root.crossroadsPath, "shortcut", "reset"] : [root.crossroadsPath, "shortcut", "set", combo])
  }

  function runShortcut(command) {
    if (shortcutProc.running) return
    shortcutProc.command = command
    shortcutProc.running = true
  }

  function writeNextTag() {
    if (tagProc.running || root.tagQueue.length === 0) return
    tagProc.command = root.tagQueue[0]
    root.tagQueue = root.tagQueue.slice(1)
    tagProc.running = true
  }

  Component.onCompleted: refresh()

  Process {
    id: fetchProc
    command: [root.crossroadsPath, "fetch"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSnapshot(text)
        if (parsed) root.snapshot = parsed
        root.runFailed = !parsed
      }
    }
  }

  Process {
    id: calendarsProc
    command: [root.crossroadsPath, "calendars", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.listing = Model.parseListing(text) || []
    }
  }

  Process {
    id: tagProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.tagError = String(text || "").trim().slice(0, 200)
    }
    onExited: function(exitCode) {
      // A failed write: show what's really saved, and drop the rest of the queue.
      if (exitCode !== 0) {
        root.tagQueue = []
        root.listing = null
        root.loadCalendars()
      }
      if (root.tagQueue.length > 0) root.writeNextTag()
      else root.refresh()
    }
  }

  // Prints the shortcut in force after the command, or an error on stderr.
  Process {
    id: shortcutProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var saved = String(text || "").trim()
        if (/^[A-Z0-9 +]{1,40}$/.test(saved)) root.shortcut = saved
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.shortcutError = String(text || "").trim().replace(/^crossroads: /, "").slice(0, 200)
    }
  }

  Timer {
    interval: Math.max(1, root.refreshMinutes) * 60 * 1000
    running: root.refreshMinutes > 0
    repeat: true
    onTriggered: root.refresh()
  }

  // Bound in Hyprland as hl.dsp.global("crossroads:toggle").
  GlobalShortcut {
    appid: "crossroads"
    name: "toggle"
    description: "Toggle the Crossroads modal"
    onPressed: root.toggleModal()
  }
}
