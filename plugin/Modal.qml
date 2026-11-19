import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The Crossroads modal: overlaps, today and unread mail at a glance, with a
// search across everything. Toggled by the service's global shortcut.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null  // set by the shell from this plugin's service entry

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property int rangeDays: Model.DEFAULT_RANGE
  property date now: new Date()
  // Vim preset only: "insert" types into the search, "normal" moves with h/j/k/l.
  property string mode: "insert"
  // "main" or "settings".
  property string view: "main"
  property int settingsIndex: 0
  // True while waiting for the new shortcut to be pressed.
  property bool capturing: false
  // The key before, so vim's gg can be recognized.
  property string previousKey: ""

  readonly property var snapshot: service ? service.snapshot : null
  readonly property var sections: Model.modalSections(snapshot, now, rangeDays, filterText)
  readonly property int count: Model.itemCount(sections)
  readonly property var todayEvents: Model.eventsInRange(snapshot, now, 0)
  readonly property var todayWindow: Model.dayWindow(todayEvents, now)
  readonly property string keyPreset: service ? Model.keyPreset(service.keys) : "default"
  readonly property var settingsRows: Model.settingsRows(service ? service.entry : null, service ? service.listing : null, service ? service.shortcut : "")
  readonly property var status: Model.statusLine(service ? service.refreshing : false, snapshot, service ? service.runFailed : false)

  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property string fontFamily: Style.font.menuFamily
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)
  readonly property int pad: Style.spacing.md

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  readonly property color personalColor: Commons.Color.accent
  readonly property color workColor: root.foreground

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.now = new Date()
    root.mode = Model.initialMode(root.keyPreset)
    root.view = "main"
    root.capturing = false
    root.previousKey = ""
    root.rangeDays = root.service ? root.service.settings.defaultRange : Model.DEFAULT_RANGE
    flick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide("georgef.crossroads")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    flick.contentY = 0
  }

  function move(direction) {
    root.selectedIndex = Model.move(root.sections, root.selectedIndex, direction)
  }

  // Key names for Model.keyAction; anything else is the typed character.
  function keyName(event) {
    var names = {}
    names[Qt.Key_Up] = "Up"; names[Qt.Key_Down] = "Down"
    names[Qt.Key_Tab] = "Tab"; names[Qt.Key_Backtab] = "Backtab"
    names[Qt.Key_Return] = "Return"; names[Qt.Key_Enter] = "Return"; names[Qt.Key_Escape] = "Escape"
    names[Qt.Key_Backspace] = "Backspace"
    var reading = Util.readingKey(event)
    if (reading === Qt.Key_Left) return "Left"
    if (reading === Qt.Key_Right) return "Right"
    if (names[event.key]) return names[event.key]
    if (event.key === Qt.Key_R) return "r"
    if (event.key === Qt.Key_Comma) return ","
    return event.text
  }

  // Returns false when the key isn't the modal's, so it's left unhandled.
  function handleKey(event) {
    if (root.view === "settings") return root.handleSettingsKey(event)
    var control = (event.modifiers & Qt.ControlModifier) !== 0
    var action = Model.keyAction(root.keyName(event), control, root.keyPreset, root.mode, root.previousKey)
    root.previousKey = action === "pending" ? "g" : ""
    if (action === "first" || action === "last") root.selectedIndex = Model.edge(root.sections, action)
    else if (action === "pending") {}
    else if (action === "up" || action === "down" || action === "left" || action === "right") root.move(action)
    else if (action === "open") root.openSelected()
    else if (action === "refresh") { if (root.service) root.service.refresh() }
    else if (action === "rangeNext") root.rangeDays = Model.nextRange(root.rangeDays, 1, true)
    else if (action === "rangePrev") root.rangeDays = Model.nextRange(root.rangeDays, -1, true)
    else if (action === "normalMode") root.mode = "normal"
    else if (action === "insertMode") root.mode = "insert"
    else if (action === "close") root.dismiss()
    else if (action === "settings") root.openSettings()
    else if (action === "clearOrClose") { if (root.filterText) root.setFilter(""); else root.dismiss() }
    else if (action === "ignore") {}
    else if (Util.editsFilter(event, root.filterText)) root.setFilter(Util.editedFilter(event, root.filterText))
    else if (!control && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) root.setFilter(root.filterText + event.text)
    else return false
    return true
  }

  function openSelected() {
    var link = Model.linkOf(Model.itemAt(root.sections, root.selectedIndex))
    if (!link) return
    Util.execArgv(["omarchy-launch-browser", link])
    root.dismiss()
  }

  function openSettings() {
    root.view = "settings"
    root.settingsIndex = 0
    root.previousKey = ""
    root.capturing = false
    flick.contentY = 0
    if (root.service) {
      root.service.loadCalendars()
      root.service.loadShortcut()
    }
  }

  function closeSettings() {
    root.view = "main"
    flick.contentY = 0
  }

  // A setting saves to shell.json; a calendar tag goes through `crossroads tag`.
  function changeRow(row, value) {
    if (!row || !root.service) return
    if (row.kind === "setting") root.service.saveSetting(row.key, value)
    else if (value !== row.value) root.service.setTag(row, value)
  }

  // The key that, with modifiers, makes a shortcut: "A"-"Z", "0"-"9", "F1"-"F12" or "SPACE".
  function shortcutKeyName(event) {
    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) return String.fromCharCode(event.key)
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) return String.fromCharCode(event.key)
    if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) return "F" + (event.key - Qt.Key_F1 + 1)
    if (event.key === Qt.Key_Space) return "SPACE"
    return ""
  }

  // Combinations Hyprland already binds never reach here; the CLI checks again.
  function captureShortcut(event) {
    if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
      root.capturing = false
      return true
    }
    var combo = Model.shortcutFromKey({
      super: (event.modifiers & Qt.MetaModifier) !== 0,
      ctrl: (event.modifiers & Qt.ControlModifier) !== 0,
      alt: (event.modifiers & Qt.AltModifier) !== 0,
      shift: (event.modifiers & Qt.ShiftModifier) !== 0
    }, root.shortcutKeyName(event))
    if (combo) {
      root.capturing = false
      if (root.service) root.service.setShortcut(combo)
    }
    return true
  }

  function handleSettingsKey(event) {
    if (root.capturing) return root.captureShortcut(event)
    var control = (event.modifiers & Qt.ControlModifier) !== 0
    var action = Model.settingsKeyAction(root.keyName(event), control, root.keyPreset, root.previousKey)
    var row = root.settingsRows[root.settingsIndex]
    root.previousKey = action === "pending" ? "g" : ""
    if (action === "first") root.settingsIndex = 0
    else if (action === "last") root.settingsIndex = Math.max(0, root.settingsRows.length - 1)
    else if (action === "up") root.settingsIndex = Math.max(0, root.settingsIndex - 1)
    else if (action === "down") root.settingsIndex = Math.min(root.settingsRows.length - 1, root.settingsIndex + 1)
    else if (row && row.kind === "shortcut" && action === "next") root.capturing = true
    else if (row && row.kind === "shortcut" && action === "reset") { if (root.service) root.service.setShortcut("reset") }
    else if (row && row.kind === "shortcut") {}
    else if (action === "next" && row) root.changeRow(row, Model.cycle(row.options, row.value, 1))
    else if (action === "previous" && row) root.changeRow(row, Model.cycle(row.options, row.value, -1))
    else if (action === "back") root.closeSettings()
    return true
  }

  function ensureVisible(item) {
    var y = item.mapToItem(flick.contentItem, 0, 0).y
    if (y < flick.contentY) flick.contentY = y
    else if (y + item.height > flick.contentY + flick.height) flick.contentY = y + item.height - flick.height
  }

  function clock(iso) {
    return new Date(iso).toLocaleTimeString(root.locale, Locale.ShortFormat)
  }

  function dayLabel(iso) {
    return new Date(iso).toLocaleDateString(root.locale, "ddd d MMM")
  }

  function timeText(event, withDay) {
    var time = event.allDay ? strings.t("events.allDay") : root.clock(event.start) + "–" + root.clock(event.end)
    return withDay ? root.dayLabel(event.start) + "  " + time : time
  }

  function ago(iso) {
    var minutes = Math.max(0, Math.round((root.now - new Date(iso)) / 60000))
    if (minutes < 60) return strings.t("age.minutes").arg(Commons.I18n.formatNumber(minutes))
    if (minutes < 1440) return strings.t("age.hours").arg(Commons.I18n.formatNumber(Math.round(minutes / 60)))
    return strings.t("age.days").arg(Commons.I18n.formatNumber(Math.round(minutes / 1440)))
  }

  function sectionTitle(key) {
    if (key === "overlaps") return strings.t("section.overlaps")
    if (key === "today") return strings.t("section.today").arg(root.dayLabel(root.now.toISOString()))
    if (key === "events") return strings.t("section.events")
    return strings.t("mail.title")
  }

  function statusText() {
    if (root.status.kind === "refreshing") return strings.t("status.refreshing")
    if (root.status.kind === "failed") return strings.t("status.runFailed")
    if (root.status.kind === "updated") return strings.t("status.updated").arg(root.clock(root.status.time))
    return strings.t("status.fetching")
  }

  function rangeLabel(days) {
    return days === 0 ? strings.t("range.today") : strings.t("range.days").arg(Commons.I18n.formatNumber(days))
  }

  // ---- Building blocks.

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component SectionTitle: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  // A soft card: tinted fill and a colored edge, brighter when selected.
  component Tile: Rectangle {
    property color tint: root.foreground
    property bool selected: false
    radius: Style.cornerRadius
    color: Util.alpha(tint, selected ? 0.22 : 0.08)
    border.width: Math.max(1, Style.spacing.hairline)
    border.color: Util.alpha(tint, selected ? 0.9 : 0.25)
  }

  component OverlapCard: Tile {
    id: overlapCard
    property var item: null  // set by the Repeater from modelData
    readonly property var card: item.value
    readonly property var window: Model.cardWindow(card)
    readonly property var shared: Model.timelineSpan(card.start, card.end, window.start, window.end)
    readonly property int minutes: Math.round((new Date(card.end) - new Date(card.start)) / 60000)
    width: content.width
    height: cardColumn.implicitHeight + root.pad * 2
    tint: Model.cardColor(card, root.personalColor, root.workColor)
    selected: item.index === root.selectedIndex
    onSelectedChanged: if (selected) root.ensureVisible(overlapCard)

    Column {
      id: cardColumn
      x: root.pad
      y: root.pad
      width: parent.width - root.pad * 2
      spacing: Style.space(8)

      Label {
        width: parent.width
        text: root.dayLabel(overlapCard.card.start) + "  ·  " + strings.tn("card.overlap", overlapCard.minutes).arg(Commons.I18n.formatNumber(overlapCard.minutes))
        color: overlapCard.tint
        font.bold: true
      }

      // Mini timeline: one bar per event, the shared window highlighted across both.
      Item {
        id: timeline
        width: parent.width
        height: Style.space(26)

        Rectangle {
          x: overlapCard.shared.x * timeline.width
          width: Math.max(Style.space(2), overlapCard.shared.width * timeline.width)
          height: parent.height
          radius: Style.space(3)
          color: Util.alpha(overlapCard.tint, 0.35)
        }

        Repeater {
          model: overlapCard.card.events

          Rectangle {
            required property var modelData
            required property int index
            readonly property var span: Model.timelineSpan(modelData.start, modelData.end, overlapCard.window.start, overlapCard.window.end)
            x: span.x * timeline.width
            y: Style.space(3) + index * Style.space(12)
            width: Math.max(Style.space(2), span.width * timeline.width)
            height: Style.space(8)
            radius: height / 2
            color: Model.tagColor(modelData.tag, root.personalColor, root.workColor)
          }
        }
      }

      Repeater {
        model: overlapCard.card.events

        Row {
          required property var modelData
          width: cardColumn.width
          spacing: Style.space(8)

          Rectangle {
            width: Style.space(8); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Model.tagColor(modelData.tag, root.personalColor, root.workColor)
          }
          Label {
            width: Style.space(120)
            text: root.timeText(modelData, false)
            color: root.dim
          }
          Label {
            width: parent.width - Style.space(260)
            text: modelData.title
          }
          Label {
            width: Style.space(110)
            horizontalAlignment: Text.AlignRight
            text: modelData.calendarName
            color: root.dim
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component EventRow: Rectangle {
    id: eventRow
    property var item: null  // set by the Repeater from modelData
    property bool withDay: false
    readonly property var event: item.value
    readonly property bool selected: item.index === root.selectedIndex
    readonly property bool flagged: event.kind !== "none"
    readonly property bool active: event.status === "accepted" || event.status === "tentative"
    readonly property color tint: Model.eventColor(event, root.personalColor, root.workColor)
    width: parent ? parent.width : 0
    height: rowContent.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: selected ? root.selectedBackground : (flagged ? Util.alpha(tint, 0.14) : "transparent")
    onSelectedChanged: if (selected) root.ensureVisible(eventRow)

    Row {
      id: rowContent
      x: Style.space(8)
      width: parent.width - Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Rectangle {
        width: Style.space(8); height: width; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: eventRow.tint
        opacity: eventRow.flagged ? 1 : 0.6
      }
      Label {
        width: eventRow.withDay ? Style.space(200) : Style.space(120)
        text: root.timeText(eventRow.event, eventRow.withDay)
        color: eventRow.flagged ? eventRow.tint : root.dim
      }
      Label {
        width: parent.width - (eventRow.withDay ? Style.space(340) : Style.space(260))
        text: eventRow.event.title
        color: eventRow.active ? root.foreground : root.dim
        font.strikeout: !eventRow.active
      }
      Label {
        width: Style.space(110)
        horizontalAlignment: Text.AlignRight
        text: eventRow.event.calendarName
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  component MailCard: Tile {
    id: mailCard
    property var item: null  // set by the Repeater from modelData
    readonly property var mail: item.value
    selected: item.index === root.selectedIndex
    height: mailColumn.implicitHeight + root.pad * 2
    onSelectedChanged: if (selected) root.ensureVisible(mailCard)

    Column {
      id: mailColumn
      x: root.pad
      y: root.pad
      width: parent.width - root.pad * 2
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: sender.implicitHeight
        Label {
          id: sender
          width: parent.width - age.implicitWidth - Style.space(8)
          text: mailCard.mail.sender
          font.bold: true
        }
        Label {
          id: age
          anchors.right: parent.right
          text: root.ago(mailCard.mail.received)
          color: root.dim
          font.pixelSize: Style.font.bodySmall
        }
      }
      Label {
        width: parent.width
        text: mailCard.mail.subject
      }
      Label {
        width: parent.width
        text: mailCard.mail.account
        color: root.dim
        font.pixelSize: Style.font.caption
      }
    }
  }

  component KeyHint: Row {
    property string label
    property string keys
    spacing: Style.space(6)
    Label { visible: label !== ""; text: label; color: root.dim; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
    Rectangle {
      width: keyText.implicitWidth + Style.space(10)
      height: keyText.implicitHeight + Style.space(4)
      radius: Style.space(4)
      color: Util.alpha(root.foreground, 0.08)
      Label { id: keyText; anchors.centerIn: parent; text: keys; color: root.dim; font.pixelSize: Style.font.caption }
    }
  }

  // ---- Clock, so "today" and the now marker stay right while open.
  Timer {
    interval: 60 * 1000
    running: root.opened
    repeat: true
    onTriggered: root.now = new Date()
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "crossroads"

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: surface
      width: Math.min(Style.space(760), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.handleKey(event)) event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: surface.contentTopInset
        anchors.rightMargin: surface.contentRightInset
        anchors.bottomMargin: surface.contentBottomInset
        anchors.leftMargin: surface.contentLeftInset
        spacing: root.pad

        // ---- Search.
        Row {
          id: searchRow
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "\u{f00ed}"  // nf-md-calendar
            color: Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
          Label {
            width: parent.width - Style.space(48)
            anchors.verticalCenter: parent.verticalCenter
            text: root.view === "settings" ? strings.t("settings.title") : (root.filterText || strings.t("modal.placeholder"))
            color: root.view === "settings" || root.filterText ? root.foreground : root.dim
            font.pixelSize: Style.font.heading
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.12) }

        // ---- Sections.
        Flickable {
          id: flick
          width: parent.width
          height: parent.height - searchRow.height - footer.height - Style.spacing.hairline * 2 - root.pad * 4
          contentWidth: width
          contentHeight: root.view === "settings" ? settingsView.implicitHeight : content.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          SettingsView {
            id: settingsView
            visible: root.view === "settings"
            width: flick.width
            rows: root.settingsRows
            listing: root.service ? root.service.listing : null
            selectedIndex: root.settingsIndex
            saving: root.service ? root.service.tagging : false
            saveError: root.service ? root.service.tagError : ""
            capturing: root.capturing
            shortcutSaving: root.service ? root.service.shortcutSaving : false
            shortcutError: root.service ? root.service.shortcutError : ""
            onChangeShortcut: function(row) {
              root.settingsIndex = row.index
              root.capturing = true
            }
            onResetShortcut: function(row) {
              root.settingsIndex = row.index
              if (root.service) root.service.setShortcut("reset")
            }
            strings: strings
            foreground: root.foreground
            selectedBackground: root.selectedBackground
            personalColor: root.personalColor
            workColor: root.workColor
            fontFamily: root.fontFamily
            onChoose: function(row, value) {
              root.settingsIndex = row.index
              root.changeRow(row, value)
            }
            onRowSelected: function(item) { root.ensureVisible(item) }
          }

          Column {
            id: content
            visible: root.view === "main"
            width: flick.width
            spacing: Style.space(14)

            Label {
              visible: root.snapshot === null
              text: root.service && root.service.runFailed ? strings.t("status.runFailed") : strings.t("status.fetching")
              color: root.dim
            }

            Label {
              visible: root.snapshot !== null && root.filterText !== "" && root.count === 0
              text: strings.t("modal.noMatches")
              color: root.dim
            }

            Repeater {
              model: root.snapshot ? root.sections : []

              Column {
                id: section
                required property var modelData
                width: content.width
                spacing: Style.space(8)

                SectionTitle { text: root.sectionTitle(section.modelData.key).toUpperCase() }

                // Overlap cards, one per collision.
                Column {
                  visible: section.modelData.key === "overlaps"
                  width: parent.width
                  spacing: Style.space(8)
                  Repeater {
                    model: section.modelData.key === "overlaps" ? section.modelData.items : []
                    OverlapCard { item: modelData }
                  }
                }

                // Today: a day strip, then the list. Search results: the list alone.
                Tile {
                  visible: section.modelData.key === "today" || section.modelData.key === "events"
                  width: parent.width
                  height: visible ? eventsColumn.implicitHeight + root.pad * 2 : 0

                  Column {
                    id: eventsColumn
                    x: root.pad
                    y: root.pad
                    width: parent.width - root.pad * 2
                    spacing: Style.space(4)

                    Item {
                      id: strip
                      visible: section.modelData.key === "today"
                      width: parent.width
                      height: visible ? Style.space(30) : 0

                      Rectangle {
                        y: Style.space(4)
                        width: parent.width
                        height: Style.space(10)
                        radius: height / 2
                        color: Util.alpha(root.foreground, 0.06)
                      }

                      Repeater {
                        model: root.todayEvents.filter(function(e) { return !e.allDay })

                        Rectangle {
                          required property var modelData
                          readonly property var span: Model.timelineSpan(modelData.start, modelData.end, root.todayWindow.start, root.todayWindow.end)
                          x: span.x * strip.width
                          y: Style.space(4)
                          width: Math.max(Style.space(3), span.width * strip.width)
                          height: Style.space(10)
                          radius: height / 2
                          color: Model.eventColor(modelData, root.personalColor, root.workColor)
                          opacity: modelData.kind === "none" ? 0.6 : 1
                        }
                      }

                      Rectangle {
                        readonly property var span: Model.timelineSpan(root.now, root.now, root.todayWindow.start, root.todayWindow.end)
                        x: span.x * strip.width
                        width: Style.space(2)
                        height: Style.space(18)
                        color: Commons.Color.urgent
                      }

                      Label {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        text: root.clock(root.todayWindow.start.toISOString())
                        color: root.dim
                        font.pixelSize: Style.font.caption
                      }
                      Label {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: root.clock(root.todayWindow.end.toISOString())
                        color: root.dim
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Label {
                      visible: section.modelData.items.length === 0
                      text: strings.t("events.empty")
                      color: root.dim
                    }

                    Repeater {
                      model: section.modelData.key === "today" || section.modelData.key === "events" ? section.modelData.items : []
                      EventRow { item: modelData; withDay: section.modelData.key === "events" }
                    }
                  }
                }

                // Unread mail, two cards per row.
                Flow {
                  visible: section.modelData.key === "mail"
                  width: parent.width
                  spacing: Style.space(8)

                  Label {
                    visible: section.modelData.items.length === 0
                    text: strings.t("mail.empty")
                    color: root.dim
                  }

                  Repeater {
                    model: section.modelData.key === "mail" ? section.modelData.items : []
                    MailCard { item: modelData; width: (content.width - Style.space(8)) / 2 }
                  }
                }
              }
            }

            Repeater {
              model: root.snapshot ? root.snapshot.errors : []
              Text {
                required property var modelData
                width: content.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: modelData.source + ": " + modelData.message
                color: Commons.Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Util.alpha(root.foreground, 0.12) }

        // ---- Footer: range and freshness, then keys.
        Column {
          id: footer
          width: parent.width
          spacing: Style.space(8)

          Item {
            visible: root.view === "main"
            width: parent.width
            height: visible ? rangeRow.implicitHeight : 0

            Row {
              id: rangeRow
              spacing: Style.space(6)

              Repeater {
                model: Model.RANGES

                Rectangle {
                  required property int modelData
                  readonly property bool selected: modelData === root.rangeDays
                  width: rangeText.implicitWidth + Style.space(24)
                  height: rangeText.implicitHeight + Style.space(12)
                  radius: Style.cornerRadius
                  color: selected ? root.selectedBackground : Util.alpha(root.foreground, 0.04)
                  border.width: Math.max(1, Style.spacing.hairline)
                  border.color: selected ? Commons.Color.accent : "transparent"

                  Label {
                    id: rangeText
                    anchors.centerIn: parent
                    text: root.rangeLabel(modelData)
                    color: parent.selected ? root.foreground : root.dim
                    font.bold: parent.selected
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.rangeDays = modelData
                  }
                }
              }

              KeyHint { anchors.verticalCenter: parent.verticalCenter; label: ""; keys: "Tab" }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                visible: root.status.kind === "refreshing"
                textFormat: Text.PlainText
                text: "\u{f0450}"  // nf-md-refresh
                color: Commons.Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                RotationAnimator on rotation {
                  running: root.status.kind === "refreshing" && !Style.reduceMotion
                  from: 0; to: 360
                  duration: Style.duration(800)
                  loops: Animation.Infinite
                }
              }
              Label {
                text: root.statusText()
                color: root.status.kind === "failed" ? Commons.Color.urgent : root.dim
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Item {
            width: parent.width
            height: hintRow.implicitHeight

            Row {
              id: hintRow
              visible: root.view === "main"
              spacing: Style.space(14)
              KeyHint { label: strings.t("hint.move"); keys: root.keyPreset === "vim" && root.mode === "normal" ? "h j k l" : "↑ ↓ ← →" }
              KeyHint { label: strings.t("hint.open"); keys: "↵" }
              KeyHint { label: strings.t("hint.refresh"); keys: "Ctrl R" }
              KeyHint {
                label: strings.t("hint.settings")
                keys: "Ctrl ,"
                TapHandler { onTapped: root.openSettings() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
              }
            }

            Row {
              readonly property var row: root.settingsRows[root.settingsIndex]
              readonly property bool onShortcut: row !== undefined && row.kind === "shortcut"
              visible: root.view === "settings" && !root.capturing
              spacing: Style.space(14)
              KeyHint { label: strings.t("hint.move"); keys: root.keyPreset === "vim" ? "j k" : "↑ ↓" }
              KeyHint { label: strings.t("hint.change"); keys: parent.onShortcut ? "↵" : (root.keyPreset === "vim" ? "h l ↵" : "← → ↵") }
              KeyHint { visible: parent.onShortcut; label: strings.t("hint.reset"); keys: "⌫" }
              KeyHint { label: strings.t("hint.back"); keys: "Esc" }
            }

            Row {
              visible: root.view === "settings" && root.capturing
              spacing: Style.space(14)
              Label { text: strings.t("shortcut.press"); color: Commons.Color.accent; font.bold: true; font.pixelSize: Style.font.bodySmall }
              KeyHint { label: strings.t("hint.cancel"); keys: "Esc" }
            }

            Label {
              visible: root.keyPreset === "vim" && root.view === "main"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.mode === "normal" ? strings.t("mode.normal") : strings.t("mode.insert")
              color: root.mode === "normal" ? Commons.Color.accent : root.dim
              font.bold: true
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
