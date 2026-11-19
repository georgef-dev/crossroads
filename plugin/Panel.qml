import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Crossroads: calendar overlaps and unread mail. The plugin's service fetches;
// this widget filters and draws.
Panel {
  id: root
  moduleName: "georgef.crossroads"
  ipcTarget: "georgef.crossroads"


  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("georgef.crossroads") : null
  readonly property var snapshot: service ? service.snapshot : null
  readonly property string runError: service && service.runFailed ? strings.t("status.runFailed") : ""
  property int rangeDays: Model.DEFAULT_RANGE
  // Bumped by the clock so ranges roll over at midnight without a fetch.
  property date now: new Date()

  readonly property var visibleEvents: Model.eventsInRange(snapshot, now, rangeDays)
  readonly property var days: Model.groupByDay(visibleEvents, now)
  readonly property int flagged: Model.flaggedCount(visibleEvents)
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  readonly property color personalColor: Commons.Color.accent
  readonly property color workColor: root.foreground

  function refresh() {
    if (service) service.refresh()
  }

  function timeText(event) {
    if (event.allDay) return strings.t("events.allDay")
    return new Date(event.start).toLocaleTimeString(locale, Locale.ShortFormat)
      + "–" + new Date(event.end).toLocaleTimeString(locale, Locale.ShortFormat)
  }

  function rangeLabel(days) {
    return days === 0 ? strings.t("range.today") : strings.t("range.days").arg(Commons.I18n.formatNumber(days))
  }

  // Settings live in this widget's shell.json entry; the service reads and saves them.
  Binding {
    target: root.service
    property: "entry"
    value: root.settings
    when: root.service !== null
  }

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Mark {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          size: button.iconSize
          color: root.barForeground
        }
      }
    }
    labelText: root.flagged > 0 ? Commons.I18n.formatNumber(root.flagged) : ""
    tooltipText: ""

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.rangeDays = Model.nextRange(root.rangeDays, dx) }
      onTextKey: function(t) { if (t.toLowerCase() === "r") root.refresh() }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          // ---- Range picker.
          Row {
            spacing: Style.space(6)

            Repeater {
              model: Model.RANGES

              Rectangle {
                required property int modelData
                readonly property bool selected: modelData === root.rangeDays
                width: rangeText.implicitWidth + Style.space(16)
                height: rangeText.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: selected ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"

                Text {
                  id: rangeText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.rangeLabel(modelData)
                  color: parent.selected ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.rangeDays = modelData
                }
              }
            }
          }

          Text {
            visible: root.snapshot === null && root.runError === ""
            textFormat: Text.PlainText
            text: strings.t("status.fetching")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Text {
            visible: root.snapshot !== null && root.days.length === 0
            textFormat: Text.PlainText
            text: strings.t("events.empty")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---- Agenda, grouped by day.
          Repeater {
            model: root.days

            Column {
              required property var modelData
              width: column.width
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: modelData.day.toLocaleDateString(root.locale, "ddd d MMM").toUpperCase()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Repeater {
                model: modelData.events

                Rectangle {
                  id: eventItem
                  required property var modelData
                  readonly property bool flagged: modelData.kind !== "none"
                  readonly property bool active: modelData.status === "accepted" || modelData.status === "tentative"
                  readonly property color tint: Model.eventColor(modelData, root.personalColor, root.workColor)
                  width: column.width
                  height: eventRow.implicitHeight + Style.space(8)
                  radius: Style.cornerRadius
                  color: flagged ? Util.alpha(tint, 0.18) : "transparent"

                  Rectangle {
                    id: stripe
                    width: Style.space(3)
                    height: parent.height - Style.space(8)
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    radius: width / 2
                    color: parent.tint
                    opacity: parent.flagged ? 1 : 0.5
                  }

                  Row {
                    id: eventRow
                    anchors.left: stripe.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(10)

                    Text {
                      width: Style.space(110)
                      textFormat: Text.PlainText
                      text: root.timeText(modelData)
                      color: eventItem.flagged ? eventItem.tint : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      width: eventRow.width - Style.space(120)
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: modelData.title
                      color: eventItem.active ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.strikeout: !eventItem.active
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            width: column.width
            height: Style.spacing.hairline
            color: root.foreground
            opacity: 0.12
          }

          // ---- Unread mail.
          Text {
            textFormat: Text.PlainText
            text: strings.t("mail.title").toUpperCase()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Text {
            visible: root.snapshot !== null && root.snapshot.mail.length === 0
            textFormat: Text.PlainText
            text: strings.t("mail.empty")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.snapshot ? root.snapshot.mail : []

            Column {
              required property var modelData
              width: column.width

              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: modelData.subject
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: modelData.sender + "  ·  " + modelData.account
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          // ---- Status: last update and anything that failed.
          Text {
            visible: root.snapshot !== null
            textFormat: Text.PlainText
            text: root.snapshot ? strings.t("status.updated").arg(new Date(root.snapshot.fetchedAt).toLocaleTimeString(root.locale, Locale.ShortFormat)) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: (root.runError ? [{ source: "crossroads", message: root.runError }] : []).concat(root.snapshot ? root.snapshot.errors : [])

            Text {
              required property var modelData
              width: column.width
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
    }
  }
}
