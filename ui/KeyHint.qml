import QtQuick
import qs.Commons

// A shortcut written the way Omarchy writes its own ("SUPER + B",
// "Alt + Tab"): plain text joined with " + ", no key caps. ↵ becomes Enter
// because the menu font has no return glyph and a fallback font draws it
// small and low. [D 2026-11-09]
Text {
  id: hint

  property string keys: ""
  property real zoom: 1
  property string fontFamily: Style.font.menuFamily

  readonly property var names: ({ "↵": "Enter", "⌫": "Backspace", "⎋": "Esc", "⇥": "Tab" })

  textFormat: Text.PlainText
  text: hint.keys ? hint.keys.split(" ").map(function(k) { return hint.names[k] || k }).join(" + ") : ""
  opacity: 0.45
  font.family: hint.fontFamily
  font.pixelSize: Math.round(Style.font.bodySmall * hint.zoom)
}
