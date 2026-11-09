import QtQuick
import qs.Commons
import qs.Ui

// The Ctrl+K action list (also the root filter and toast actions), drawn as
// an Omarchy popup card: popups.* colours and border, popup padding, the
// search line on top and menu-style rows. [D 2026-11-09]
BorderSurface {
  id: panel

  property var actions: []
  property string filter: ""
  property string placeholder: "Search for actions…"
  property int selectedIndex: 0
  property var look: null
  property real zoom: 1

  signal activated(string actionId)

  function px(v) { return Math.round(Style.space(v) * panel.zoom) }
  function fontPx(v) { return Math.round(v * panel.zoom) }

  readonly property var visibleActions: {
    var f = panel.filter.trim().toLowerCase()
    return panel.actions.filter(function(a) { return !f || a.title.toLowerCase().indexOf(f) >= 0 })
  }
  readonly property int rowHeight: Math.max(px(34), fontPx(Style.font.body + Style.spacing.controlPaddingY * 2 + Style.spacing.xs * 2))
  readonly property int dividerHeight: px(9)
  readonly property int innerSpacing: fontPx(Style.spacing.md)

  function move(delta) {
    var n = panel.visibleActions.length
    if (n === 0) return
    panel.selectedIndex = (panel.selectedIndex + delta + n) % n
    list.positionViewAtIndex(panel.selectedIndex, ListView.Contain)
  }

  function activateSelected() {
    var a = panel.visibleActions[panel.selectedIndex]
    if (a) panel.activated(a.id)
  }

  onFilterChanged: selectedIndex = 0
  onActionsChanged: selectedIndex = 0

  width: px(340)
  height: Math.min(px(380), contentTopInset + contentBottomInset + searchRow.height + innerSpacing + list.contentHeight)
  radius: look.radius
  color: look.popupBackground
  borderSpec: look.popupBorderSpec
  padding: fontPx(Style.spacing.popupPadding) - px(4)

  MouseArea { anchors.fill: parent }

  Item {
    id: searchRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: panel.contentTopInset
    anchors.leftMargin: panel.contentLeftInset + panel.px(8)
    anchors.rightMargin: panel.contentRightInset + panel.px(8)
    height: panel.fontPx(Style.font.title + Style.spacing.controlPaddingY)

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: panel.filter || panel.placeholder
      opacity: panel.filter ? 1 : 0.58
      color: panel.look.popupText
      elide: Text.ElideLeft
      font.family: panel.look.fontFamily
      font.pixelSize: panel.fontPx(Style.font.title)
    }
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: searchRow.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: panel.innerSpacing
    anchors.leftMargin: panel.contentLeftInset
    anchors.rightMargin: panel.contentRightInset
    anchors.bottomMargin: panel.contentBottomInset
    clip: true
    model: panel.visibleActions
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      required property var modelData
      required property int index
      readonly property bool newSection: index > 0 && panel.visibleActions[index - 1].section !== modelData.section
      readonly property bool current: index === panel.selectedIndex
      width: ListView.view.width
      height: panel.rowHeight + (newSection ? panel.dividerHeight : 0)

      Rectangle {
        visible: parent.newSection
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        y: Math.round((panel.dividerHeight - height) / 2)
        height: Style.spacing.hairline
        color: Util.alpha(panel.look.popupText, 0.2)
      }

      BorderSurface {
        id: actionRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: panel.rowHeight
        radius: panel.look.radius
        color: current ? panel.look.selectedBackground : "transparent"
        borderSpec: current ? panel.look.selectedBorderSpec : Border.none()

        Text {
          id: actionIcon
          anchors.left: parent.left
          anchors.leftMargin: actionRow.borderLeft + panel.px(8)
          anchors.verticalCenter: parent.verticalCenter
          width: panel.px(20)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: modelData.icon || ""
          color: current ? panel.look.selectedText : panel.look.popupText
          font.family: modelData.icon === "" ? "omarchy" : panel.look.fontFamily
          font.pixelSize: panel.fontPx(Style.font.icon)
        }

        Text {
          anchors.left: actionIcon.right
          anchors.leftMargin: panel.px(8)
          anchors.right: keys.left
          anchors.rightMargin: panel.px(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.title
          color: current ? panel.look.selectedText : panel.look.popupText
          elide: Text.ElideRight
          font.family: panel.look.fontFamily
          font.pixelSize: panel.fontPx(Style.font.title)
        }

        KeyHint {
          id: keys
          anchors.right: parent.right
          anchors.rightMargin: actionRow.borderRight + panel.px(8)
          anchors.verticalCenter: parent.verticalCenter
          keys: modelData.shortcut || ""
          color: panel.look.popupText
          fontFamily: panel.look.fontFamily
          zoom: panel.zoom
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: panel.selectedIndex = index
          onClicked: { panel.selectedIndex = index; panel.activateSelected() }
        }
      }
    }
  }
}
