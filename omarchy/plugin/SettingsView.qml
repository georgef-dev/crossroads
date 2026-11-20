import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The settings view inside the modal: general settings, a tag for every
// calendar, and the configured accounts. The modal owns keys and saving;
// this view draws rows and reports clicks.
Column {
  id: root

  property var rows: []
  property var listing: null
  property int selectedIndex: 0
  property bool saving: false
  property string saveError: ""
  property bool capturing: false
  property bool shortcutSaving: false
  property string shortcutError: ""
  property var strings: null
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color personalColor: Commons.Color.accent
  property color workColor: foreground
  property string fontFamily: Style.font.menuFamily

  signal choose(var row, var value)
  signal changeShortcut(var row)
  signal resetShortcut(var row)
  signal rowSelected(var item)

  spacing: Style.space(10)

  function t(key) {
    return root.strings ? root.strings.t(key) : key
  }

  function optionLabel(row, value) {
    if (row.key === "refreshMinutes") return value === 0 ? t("option.off") : t("option.minutes").arg(Commons.I18n.formatNumber(value))
    if (row.key === "keys") return t("option." + value)
    if (row.key === "defaultRange") return value === 0 ? t("range.today") : t("range.days").arg(Commons.I18n.formatNumber(value))
    return t("option." + value)
  }

  function rowLabel(row) {
    return row.kind === "setting" ? t("setting." + row.key) : row.name
  }

  function calendarRows(account) {
    return root.rows.filter(function(row) { return row.kind === "calendar" && row.account === account.account })
  }

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

  // One setting or calendar: a label on the left, its options on the right.
  component SettingRow: Rectangle {
    id: settingRow
    property var row: null
    readonly property bool selected: row !== null && row.index === root.selectedIndex
    width: root.width
    height: optionsRow.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: selected ? root.selectedBackground : "transparent"
    onSelectedChanged: if (selected) root.rowSelected(settingRow)

    Rectangle {
      visible: settingRow.row !== null && settingRow.row.kind === "calendar"
      x: Style.space(8)
      width: Style.space(8); height: width; radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: settingRow.row && settingRow.row.value === "work" ? root.workColor : root.personalColor
      opacity: settingRow.row && settingRow.row.value === "off" ? 0.2 : 1
    }

    Label {
      x: Style.space(24)
      width: parent.width - optionsRow.width - Style.space(36)
      anchors.verticalCenter: parent.verticalCenter
      text: settingRow.row ? root.rowLabel(settingRow.row) : ""
    }

    Row {
      id: optionsRow
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Repeater {
        model: settingRow.row ? settingRow.row.options : []

        Rectangle {
          required property var modelData
          readonly property bool chosen: settingRow.row !== null && modelData === settingRow.row.value
          width: optionText.implicitWidth + Style.space(18)
          height: optionText.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: chosen ? Util.alpha(Commons.Color.accent, 0.22) : Util.alpha(root.foreground, 0.04)
          border.width: Math.max(1, Style.spacing.hairline)
          border.color: chosen ? Commons.Color.accent : "transparent"

          Label {
            id: optionText
            anchors.centerIn: parent
            text: root.optionLabel(settingRow.row, modelData)
            color: parent.chosen ? root.foreground : root.dim
            font.bold: parent.chosen
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.choose(settingRow.row, modelData)
          }
        }
      }
    }
  }

  // The shortcut: what it is now, with Change and Reset.
  component ShortcutRow: Rectangle {
    id: shortcutRow
    property var row: null
    readonly property bool selected: row !== null && row.index === root.selectedIndex
    width: root.width
    height: shortcutContent.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: selected ? root.selectedBackground : "transparent"
    onSelectedChanged: if (selected) root.rowSelected(shortcutRow)

    Label {
      x: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      text: root.t("setting.shortcut")
    }

    Row {
      id: shortcutContent
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Rectangle {
        width: comboText.implicitWidth + Style.space(18)
        height: comboText.implicitHeight + Style.space(8)
        radius: Style.cornerRadius
        color: Util.alpha(Commons.Color.accent, root.capturing ? 0.35 : 0.22)
        border.width: Math.max(1, Style.spacing.hairline)
        border.color: Commons.Color.accent

        Label {
          id: comboText
          anchors.centerIn: parent
          text: root.capturing ? root.t("shortcut.press")
            : (root.shortcutSaving ? root.t("shortcut.saving") : Model.shortcutLabel(shortcutRow.row ? shortcutRow.row.value : ""))
          font.bold: true
          font.pixelSize: Style.font.bodySmall
        }
      }

      Repeater {
        model: ["change", "reset"]

        Rectangle {
          required property string modelData
          width: actionText.implicitWidth + Style.space(18)
          height: actionText.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: Util.alpha(root.foreground, 0.04)

          Label {
            id: actionText
            anchors.centerIn: parent
            text: root.t("shortcut." + modelData)
            color: root.dim
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData === "change" ? root.changeShortcut(shortcutRow.row) : root.resetShortcut(shortcutRow.row)
          }
        }
      }
    }
  }

  SectionTitle { text: root.t("settings.general").toUpperCase() }

  Repeater {
    model: root.rows.filter(function(row) { return row.kind === "setting" })
    SettingRow { row: modelData }
  }

  Repeater {
    model: root.rows.filter(function(row) { return row.kind === "shortcut" })
    ShortcutRow { row: modelData }
  }

  Label {
    visible: root.shortcutError !== ""
    width: root.width
    wrapMode: Text.Wrap
    elide: Text.ElideNone
    text: root.shortcutError
    color: Commons.Color.urgent
    font.pixelSize: Style.font.caption
  }

  SectionTitle { text: root.t("settings.calendars").toUpperCase(); topPadding: Style.space(6) }

  Label {
    visible: root.listing === null
    text: root.t("settings.loading")
    color: root.dim
  }

  Repeater {
    model: root.listing || []

    Column {
      id: accountCalendars
      required property var modelData
      width: root.width
      spacing: Style.space(2)

      Label {
        width: parent.width
        text: accountCalendars.modelData.account
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        visible: accountCalendars.modelData.error !== ""
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: accountCalendars.modelData.error
        color: Commons.Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Repeater {
        model: root.calendarRows(accountCalendars.modelData)
        SettingRow { row: modelData }
      }
    }
  }

  Label {
    visible: root.saving || root.saveError !== ""
    width: root.width
    text: root.saving ? root.t("settings.saving") : root.saveError
    color: root.saving ? root.dim : Commons.Color.urgent
    font.pixelSize: Style.font.caption
  }

  SectionTitle { text: root.t("settings.accounts").toUpperCase(); topPadding: Style.space(6) }

  Repeater {
    model: root.listing || []

    Label {
      required property var modelData
      width: root.width
      text: modelData.account + "  ·  " + (modelData.provider === "google" ? "Google" : "iCloud")
        + (modelData.mail ? "  ·  " + root.t("settings.mail") : "")
    }
  }

  Label {
    width: root.width
    text: root.t("settings.addAccount").arg("crossroads auth google <email>  ·  crossroads auth icloud <apple-id>")
    color: root.dim
    font.pixelSize: Style.font.bodySmall
  }
}
