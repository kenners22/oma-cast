import QtQuick
import qs.Commons
import qs.Ui

// The About panel (Ctrl+Shift+K): label/value rows describing the selected
// row (RootSearch.aboutFor). An Omarchy popup card: popups.* colours and
// border, a PanelSectionHeader-style title. [D 2026-11-09]
BorderSurface {
  id: panel

  property string title: ""
  property var rows: []
  property var look: null
  property real zoom: 1

  function px(v) { return Math.round(Style.space(v) * panel.zoom) }
  function fontPx(v) { return Math.round(v * panel.zoom) }

  width: px(400)
  height: content.implicitHeight + contentTopInset + contentBottomInset
  radius: look.radius
  color: look.popupBackground
  borderSpec: look.popupBorderSpec
  padding: fontPx(Style.spacing.popupPadding)

  MouseArea { anchors.fill: parent }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: panel.contentTopInset
    anchors.leftMargin: panel.contentLeftInset
    anchors.rightMargin: panel.contentRightInset
    spacing: panel.px(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: panel.title
      color: panel.look.popupText
      elide: Text.ElideRight
      font.family: panel.look.fontFamily
      font.pixelSize: panel.fontPx(Style.font.title)
      font.weight: Font.Medium
    }

    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: Util.alpha(panel.look.popupText, 0.12)
    }

    Repeater {
      model: panel.rows

      Row {
        required property var modelData
        width: content.width
        spacing: panel.px(10)

        Text {
          width: panel.px(100)
          textFormat: Text.PlainText
          text: modelData.label
          color: Qt.darker(panel.look.popupText, 1.4)
          elide: Text.ElideRight
          font.family: panel.look.fontFamily
          font.pixelSize: panel.fontPx(Style.font.caption)
          font.bold: true
        }
        Text {
          width: content.width - panel.px(110)
          textFormat: Text.PlainText
          text: modelData.value
          color: panel.look.popupText
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 4
          elide: Text.ElideRight
          font.family: panel.look.fontFamily
          font.pixelSize: panel.fontPx(Style.font.bodySmall)
        }
      }
    }
  }
}
