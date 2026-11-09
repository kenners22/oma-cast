import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: row

  required property int index
  required property string rowKind
  required property string itemId
  required property string title
  required property string subtitle
  required property string glyph
  required property string glyphFont
  required property string iconName
  required property string typeLabel
  required property string alias
  required property bool checked
  required property bool disabled
  required property bool favorite
  required property string calcInput
  required property string calcResult
  required property string calcInputCaption
  required property string calcResultCaption

  property bool selected: false
  // While typing, titled sections become Omarchy's search divider. [D]
  property bool searching: false
  property var look: null
  property var appLibrary: null
  property real zoom: 1

  signal hovered(int index, var item, var mouse)
  signal clicked(int index)

  readonly property bool isSection: row.rowKind === "section"
  readonly property bool isCalculator: row.rowKind === "calculator"
  function px(v) { return Math.round(Style.space(v) * row.zoom) }
  function fontPx(v) { return Math.round(v * row.zoom) }

  // Omarchy's row metrics (plugins/menu/Menu.qml): 50 px rows, 58 with a
  // detail line, rounded only as far as the theme rounds windows. [D 2026-11-09]
  readonly property bool showsTitle: row.isSection && row.title.length > 0 && !row.searching
  readonly property bool hasDetail: row.subtitle.length > 0
  readonly property int baseRowHeight: Math.max(px(50), fontPx(Style.font.body + Style.spacing.rowPaddingX * 2))
  readonly property int detailRowHeight: Math.max(px(58), fontPx(Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2))
  readonly property bool chevron: row.typeLabel === "›"
  readonly property color ink: row.selected ? row.look.selectedText : row.look.foreground

  width: ListView.view ? ListView.view.width : 0
  height: row.isSection ? (row.showsTitle ? px(26) : (row.index === 0 ? 0 : px(17)))
    : row.isCalculator ? px(118)
    : (row.hasDetail ? row.detailRowHeight : row.baseRowHeight)

  // The inline calculator (ref 04 §1 Calculator): question on the left,
  // answer on the right, each with a caption, an arrow between them. Drawn
  // as an Omarchy row: the selected fill and border, plain detail captions.
  Loader {
    active: row.isCalculator
    anchors.fill: parent
    sourceComponent: BorderSurface {
      anchors.fill: parent
      radius: row.look.radius
      color: row.selected ? row.look.selectedBackground : Util.alpha(row.look.foreground, Style.normalFillAlpha)
      borderSpec: row.selected ? row.look.selectedBorderSpec : Border.flat(Util.alpha(row.look.foreground, 0.12), Style.normalBorderWidth)

      Repeater {
        model: row.isCalculator ? [
          { text: row.calcInput, caption: row.calcInputCaption, answer: false },
          { text: row.calcResult, caption: row.calcResultCaption, answer: true }
        ] : []

        delegate: Item {
          required property var modelData
          required property int index
          x: index === 0 ? 0 : parent.width / 2 + row.px(20)
          width: parent.width / 2 - row.px(20)
          height: parent.height

          Text {
            id: calcText
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -row.px(8)
            width: parent.width - row.px(24)
            horizontalAlignment: Text.AlignHCenter
            text: modelData.text
            color: modelData.answer && row.selected ? row.look.selectedText : row.look.foreground
            font.family: row.look.fontFamily
            font.pixelSize: row.fontPx(Style.font.display)
            font.weight: modelData.answer ? Font.DemiBold : Font.Medium
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: row.fontPx(Style.font.body)
            elide: Text.ElideRight
          }

          Text {
            visible: modelData.caption.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: calcText.bottom
            anchors.topMargin: row.px(6)
            width: Math.min(implicitWidth, parent.width - row.px(24))
            textFormat: Text.PlainText
            text: modelData.caption
            color: row.look.foreground
            opacity: 0.52
            font.family: row.look.fontFamily
            font.pixelSize: row.fontPx(Style.font.bodySmall)
            elide: Text.ElideRight
          }
        }
      }

      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -row.px(8)
        textFormat: Text.PlainText
        text: Commons.I18n.rightToLeft ? "←" : "→"
        color: row.ink
        opacity: 0.36
        font.family: row.look.fontFamily
        font.pixelSize: row.fontPx(Style.font.heading)
      }
    }
  }

  // A titled section is introduced the way Omarchy's panels do it
  // (PanelSectionHeader); an untitled one is the menu's search divider.
  Text {
    visible: row.showsTitle
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: row.px(8)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: row.px(4)
    text: row.title
    color: Qt.darker(row.look.foreground, 1.4)
    font.family: row.look.fontFamily
    font.pixelSize: row.fontPx(Style.font.caption)
    font.bold: true
  }

  Rectangle {
    visible: row.isSection && !row.showsTitle && row.index > 0
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.spacing.hairline
    color: Util.alpha(row.look.foreground, 0.2)
  }

  BorderSurface {
    id: plate
    visible: !row.isSection && !row.isCalculator
    anchors.fill: parent
    radius: row.look.radius
    color: row.selected ? row.look.selectedBackground : "transparent"
    borderSpec: row.selected ? row.look.selectedBorderSpec : Border.none()
    opacity: row.disabled ? 0.4 : 1

    Item {
      id: iconBox
      width: row.px(36)
      height: row.fontPx(Style.font.iconLarge)
      anchors.left: parent.left
      anchors.leftMargin: plate.borderLeft + row.px(8)
      // Icons sit on the label's line.
      y: textColumn.y + titleText.y + (titleText.height - height) / 2

      Image {
        anchors.centerIn: parent
        width: row.fontPx(Style.font.iconLarge)
        height: width
        visible: row.iconName.length > 0 && row.glyph.length === 0
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        source: !visible ? "" : (row.appLibrary ? row.appLibrary.iconSource(row.iconName) : Quickshell.iconPath(row.iconName, "application-x-executable"))
      }

      Text {
        anchors.centerIn: parent
        visible: row.glyph.length > 0
        textFormat: Text.PlainText
        text: row.glyph
        color: row.ink
        font.family: row.glyphFont || row.look.fontFamily
        font.pixelSize: row.glyphFont === "omarchy" ? row.fontPx(Style.font.iconLarge * 0.8) : row.fontPx(Style.font.iconLarge)
      }
    }

    // On the label's line, as Omarchy places its trailing ›.
    Item {
      id: trail
      anchors.right: parent.right
      anchors.rightMargin: plate.borderRight + row.px(8)
      y: textColumn.y + titleText.y
      width: accessories.width
      height: titleText.height

    Row {
      id: accessories
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: row.px(10)

      BorderSurface {
        visible: row.alias.length > 0
        anchors.verticalCenter: parent.verticalCenter
        height: aliasText.implicitHeight + row.px(4)
        width: aliasText.implicitWidth + row.px(12)
        radius: Math.min(4, row.look.radius)
        color: "transparent"
        borderSpec: Border.controlSpec("normal", row.look.foreground, row.look.accent)
        Text {
          id: aliasText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: row.alias
          color: row.look.foreground
          opacity: 0.7
          font.family: row.look.fontFamily
          font.pixelSize: row.fontPx(Style.font.caption)
        }
      }

      Text {
        visible: row.favorite
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: ""
        color: row.look.selectedText
        opacity: 0.8
        font.family: row.look.fontFamily
        font.pixelSize: row.fontPx(Style.font.caption)
      }

      Text {
        visible: row.checked
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "✓"
        color: row.look.selectedText
        font.family: row.look.fontFamily
        font.pixelSize: row.fontPx(Style.font.body)
      }

      // Submenus end in Omarchy's › ; times and counts show quietly.
      // (LauncherWindow.rowData drops the Command/Application kind labels.)
      Text {
        visible: row.typeLabel.length > 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.chevron ? (Commons.I18n.rightToLeft ? "‹" : "›") : row.typeLabel
        color: row.chevron ? row.ink : row.look.foreground
        opacity: row.chevron ? 0.36 : 0.52
        font.family: row.look.fontFamily
        font.pixelSize: row.chevron ? row.fontPx(Style.font.heading) : row.fontPx(Style.font.bodySmall)
      }
    }

    }

    // Label over detail, as the Omarchy menu lays out a row with a path.
    Column {
      id: textColumn
      anchors.left: iconBox.right
      anchors.leftMargin: row.px(6)
      anchors.right: trail.left
      anchors.rightMargin: row.px(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: row.px(3)

      Text {
        id: titleText
        width: parent.width
        textFormat: Text.PlainText
        text: row.title
        color: row.ink
        font.family: row.look.fontFamily
        font.pixelSize: row.fontPx(Style.font.heading)
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.subtitle
        visible: row.hasDetail
        color: row.look.foreground
        opacity: 0.52
        font.family: row.look.fontFamily
        font.pixelSize: row.fontPx(Style.font.bodySmall)
        elide: Text.ElideRight
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !row.isSection
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: function(mouse) { row.hovered(row.index, row, mouse) }
    onClicked: row.clicked(row.index)
  }
}
