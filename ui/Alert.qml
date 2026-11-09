import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A confirm dialog over the card (ref 04 §2.6 alert-store): ↵ confirms, Esc
// cancels. spec: {title, message, primary, destructive}. Drawn like Omarchy's
// own Ui/ConfirmDialog (the menu's uninstall prompt): the menu scrim, a
// card outlined in the selected-text colour, square buttons on the right,
// the destructive one in the theme's urgent colour. [D 2026-11-09]
Rectangle {
  id: alert

  property var spec: null
  property var look: null
  property real zoom: 1

  property string cancelText: "Cancel"

  signal confirmed()
  signal cancelled()

  function px(v) { return Math.round(Style.space(v) * alert.zoom) }
  function fontPx(v) { return Math.round(v * alert.zoom) }

  readonly property color danger: alert.look.urgent

  color: alert.look.scrim

  MouseArea { anchors.fill: parent; onClicked: alert.cancelled() }

  BorderSurface {
    id: box
    anchors.centerIn: parent
    width: Math.min(parent.width - alert.px(32), alert.px(370))
    height: box.contentTopInset + box.contentBottomInset + column.implicitHeight + alert.px(20) + buttons.height
    radius: alert.look.radius
    color: alert.look.background
    borderSpec: Border.flat(alert.look.selectedText, Style.normalBorderWidth)
    padding: alert.px(18)

    MouseArea { anchors.fill: parent }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: box.contentTopInset
      anchors.leftMargin: box.contentLeftInset
      anchors.rightMargin: box.contentRightInset
      spacing: alert.px(6)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: alert.spec ? alert.spec.title : ""
        color: alert.look.foreground
        wrapMode: Text.Wrap
        font.family: alert.look.fontFamily
        font.pixelSize: alert.fontPx(Style.font.title)
        font.weight: Font.Medium
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: alert.spec ? alert.spec.message : ""
        visible: text.length > 0
        color: alert.look.foreground
        opacity: 0.7
        wrapMode: Text.Wrap
        font.family: alert.look.fontFamily
        font.pixelSize: alert.fontPx(Style.font.bodySmall)
      }
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.rightMargin: box.contentRightInset
      anchors.bottom: parent.bottom
      anchors.bottomMargin: box.contentBottomInset
      spacing: alert.px(10)

      Repeater {
        model: [
          { primary: false, title: alert.cancelText },
          { primary: true, title: alert.spec ? alert.spec.primary : "OK" }
        ]

        // ↵ always confirms, so the primary button always shows as chosen.
        BorderSurface {
          required property var modelData
          readonly property bool chosen: modelData.primary
          readonly property bool destructive: modelData.primary && alert.spec && alert.spec.destructive
          width: Math.max(alert.px(88), buttonText.implicitWidth + alert.px(24))
          height: alert.px(34)
          radius: 0
          color: chosen ? (destructive ? Util.alpha(alert.danger, 0.22) : alert.look.selectedBackground) : "transparent"
          borderSpec: Border.flat(destructive
            ? (chosen ? alert.danger : Util.alpha(alert.danger, 0.56))
            : (chosen ? alert.look.selectedText : Util.alpha(alert.look.foreground, 0.38)), Style.normalBorderWidth)

          Text {
            id: buttonText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData.title
            color: destructive ? alert.danger : (chosen ? alert.look.selectedText : alert.look.foreground)
            font.family: alert.look.fontFamily
            font.pixelSize: alert.fontPx(Style.font.caption)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.primary ? alert.confirmed() : alert.cancelled()
          }
        }
      }
    }
  }
}
