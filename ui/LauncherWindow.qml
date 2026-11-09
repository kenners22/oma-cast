import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../core/RootSearch.js" as RootSearch
import "../core/Rows.js" as Rows

// Omarchy 4.0.x dropped qs.Ui.OverlayWindow; this is the same full-screen
// overlay layer the shell's own emoji picker uses.
PanelWindow {
  id: window

  required property var backend
  property var appLibrary: null
  property bool shown: false
  readonly property bool busy: window.shown && window.backend.loading
  readonly property int loadingFeedbackDelay: 500
  property bool loadingVisible: false

  onBusyChanged: {
    window.loadingVisible = false
    if (window.busy) loadingDelay.restart()
    else loadingDelay.stop()
  }

  Timer {
    id: loadingDelay
    interval: window.loadingFeedbackDelay
    onTriggered: window.loadingVisible = window.busy
  }

  signal dismissRequested()

  visible: window.shown
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omacast"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property var general: {
    window.backend.storeRevision
    var r = window.backend.ready ? window.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({ uiZoom: 1, windowMode: "expanded", escapeKeyBehavior: "pop-back-or-close", popToRootTimeout: 90, navigationBindings: "emacs" })
  }
  readonly property real zoom: window.general.uiZoom > 0 ? window.general.uiZoom : 1
  function px(value) { return Math.round(Style.space(value) * window.zoom) }

  // Everything the surface draws comes from the same theme tokens as
  // Omarchy's own menu, clipboard and emoji windows (Commons.Color.menu.*,
  // popups.* and Style.*), so `omarchy theme set` restyles it live. [D 2026-11-09]
  readonly property var look: ({
    background: Commons.Color.menu.background,
    foreground: Commons.Color.menu.text,
    accent: Commons.Color.menu.selectedText,
    selectedBackground: Commons.Color.menu.selectedBackground,
    selectedText: Commons.Color.menu.selectedText,
    selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Commons.Color.menu.selectedBorder, 0),
    scrim: Commons.Color.menu.scrim,
    urgent: Commons.Color.urgent,
    popupBackground: Commons.Color.popups.background,
    popupText: Commons.Color.popups.text,
    popupBorderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2))),
    radius: Style.cornerRadius,
    fontFamily: Style.font.menuFamily
  })
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))

  property var stack: [{ kind: "root", title: "omacast", query: "" }]
  readonly property var view: window.stack[window.stack.length - 1]
  property string query: ""
  property int selectedIndex: -1
  property var selectedRow: null
  property int searchSerial: 0
  property bool searchPending: false
  property bool actionPanelOpen: false
  property var actions: []
  property var toast: null
  property int historyIndex: -1

  // Ctrl+P root filter (RootSearch.FILTERS), Ctrl+T toast actions,
  // Ctrl+Shift+K About panel and the confirm alert.
  property string rootFilter: "all"
  property bool dropdownOpen: false
  property bool toastPanelOpen: false
  property bool aboutOpen: false
  property var aboutRows: []
  property var alert: null

  // Inline argument pills for the selected command: argFocus -1 is the
  // search field, 0.. an argument.
  property var argDefs: []
  property var argValues: ({})
  property int argFocus: -1
  property string argsForId: ""

  // Navigation bindings (ref 04 §2.8): emacs moves with Ctrl+N (Ctrl+P is the
  // dropdown); vim-motions with Ctrl+J/K, which moves the action panel to
  // Alt+K. Ctrl+B/F and Ctrl+H/L move a text cursor in Raycast; our search
  // field has none, so they do nothing here. [D]
  readonly property bool vim: window.general.navigationBindings === "vim-motions"
  readonly property string actionPanelKeys: window.vim ? "Alt K" : "Ctrl K"

  readonly property bool atRoot: window.stack.length === 1
  readonly property bool compact: window.general.windowMode === "compact" && window.atRoot && !window.query
  function tr(text) { return window.backend.tr(text) }
  readonly property string placeholder: window.view.kind === "alias" ? window.tr("Type an alias, then press Enter")
    : window.view.kind === "menu" ? window.tr("Search %1…").arg(window.tr(window.view.title))
    : window.view.kind === "calculator-history" ? window.tr("Search calculations…")
    : window.view.kind === "shortcuts" ? window.tr("Search shortcuts…")
    : window.tr("Search for apps and commands…")

  // Omarchy's card metrics (plugins/menu/Menu.qml, clipboard, emojis):
  // panel padding all round, a header sized from the title font, md spacing.
  readonly property int cardWidth: Math.min(px(750), width - Style.gapsOut * 2)
  readonly property int fullHeight: Math.min(px(500), height - Style.gapsOut * 2)
  readonly property int contentMargin: Math.round(Style.spacing.panelPadding * window.zoom)
  readonly property int contentSpacing: Math.round(Style.spacing.md * window.zoom)
  readonly property int headerHeight: Math.max(px(34), Math.round((Style.font.title + Style.spacing.controlPaddingY * 2) * window.zoom))

  ListModel { id: rows }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }


  function closePopups() {
    window.actionPanelOpen = false
    window.dropdownOpen = false
    window.toastPanelOpen = false
    window.aboutOpen = false
    window.alert = null
  }

  function prepare(payload) {
    popTimer.stop()
    if (typeof payload.query === "string") window.query = payload.query
    window.closePopups()
    window.historyIndex = -1
    window.rebuild(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  onShownChanged: {
    if (window.shown) return
    window.searchSerial++
    window.backend.cancelSearch()
    window.searchPending = false
    window.closePopups()
    var seconds = Number(window.general.popToRootTimeout)
    if (!(seconds > 0)) window.popToRoot()
    else { popTimer.interval = seconds * 1000; popTimer.restart() }
  }

  Timer {
    id: popTimer
    onTriggered: window.popToRoot()
  }

  function popToRoot() {
    window.stack = [{ kind: "root", title: "omacast", query: "" }]
    window.query = ""
    window.rootFilter = "all"
    window.rebuild(true)
  }


  function push(next) {
    var saved = window.stack.slice()
    saved[saved.length - 1] = Object.assign({}, window.view, { query: window.query, selectedIndex: window.selectedIndex })
    window.stack = saved.concat([next])
    window.query = next.kind === "alias" ? (next.value || "") : ""
    window.rebuild(true)
  }

  function pop() {
    if (window.atRoot) return
    var next = window.stack.slice(0, -1)
    var top = next[next.length - 1]
    window.stack = next
    window.query = top.query || ""
    window.rebuild(false, top.selectedIndex)
  }


  function rebuild(resetSelection, restoreIndex) {
    var serial = ++window.searchSerial
    window.backend.cancelSearch()
    pointerGate.reset()
    var keepId = !resetSelection && window.selectedRow ? window.selectedRow.itemId : ""
    window.searchPending = false
    if (window.view.kind === "alias") { Rows.update(rows, []); window.select(-1); return }
    window.searchPending = true
    var revision = window.backend.candidatesRevision
    window.backend.searchAsync({ query: window.query, view: window.view, filter: window.atRoot ? window.rootFilter : "all" }, function(result) {
      if (serial !== window.searchSerial || revision !== window.backend.candidatesRevision) return
      window.applySearch(result, keepId, restoreIndex)
      window.searchPending = false
    })
  }

  function applySearch(result, keepId, restoreIndex) {
    if (!result.ok) {
      Rows.update(rows, [])
      window.showToast("failure", result.error)
      window.select(-1)
      return
    }
    var keepIndex = -1, next = []
    for (var s = 0; s < result.data.length; s++) {
      var section = result.data[s]
      if (section.title || s > 0) next.push(window.rowData({ id: "section:" + section.id, title: section.title }, "section"))
      for (var r = 0; r < section.rows.length; r++) {
        var c = section.rows[r]
        if (c.id === keepId) keepIndex = next.length
        next.push(window.rowData(c, c.kind === "calculator" ? "calculator" : "item"))
      }
    }
    Rows.update(rows, next)
    if (restoreIndex >= 0 && restoreIndex < rows.count && window.isSelectable(restoreIndex)) window.select(restoreIndex)
    else window.select(keepIndex >= 0 ? keepIndex : window.nextSelectable(-1, 1))
  }

  // Omarchy's rows name no kind, so Command / Application / Fallback /
  // Calculator labels are dropped here (the About panel keeps them) and a
  // menu gets Omarchy's ›. omacast's own words are translated; content
  // (apps, the Omarchy menu, already translated by
  // Omarchy's catalog) is left alone. [D 2026-11-09]
  readonly property var kindLabels: ["Command", "Application", "Fallback", "Calculator", "Menu"]
  function ownText(c, kind) {
    return kind === "section" || /^(builtin|fallback|shortcut):/.test(String(c.id || ""))
  }
  function rowData(c, kind) {
    var own = window.ownText(c, kind)
    var typeLabel = String(c.typeLabel || "")
    return {
      rowKind: kind,
      itemId: String(c.id || ""),
      title: own ? window.backend.trLabel(c.title) : String(c.title || ""),
      subtitle: own ? window.backend.trLabel(c.subtitle) : String(c.subtitle || ""),
      glyph: String(c.glyph || ""),
      glyphFont: String(c.glyphFont || ""),
      iconName: String(c.iconName || ""),
      typeLabel: typeLabel === "Menu" || typeLabel === "›" ? "›" : window.kindLabels.indexOf(typeLabel) >= 0 ? "" : window.backend.trLabel(typeLabel),
      alias: String(c.alias || ""),
      checked: !!c.checked,
      disabled: !!c.disabled,
      favorite: typeof c.favoriteOrder === "number",
      calcInput: String(c.calcInput || ""),
      calcResult: String(c.calcResult || ""),
      calcInputCaption: String(c.calcInputCaption || ""),
      calcResultCaption: String(c.calcResultCaption || ""),
      argsJson: JSON.stringify(c.arguments || [])
    }
  }

  function isSelectable(index) {
    var kind = rows.get(index).rowKind
    return kind === "item" || kind === "calculator"
  }

  function nextSelectable(from, direction) {
    for (var i = from + direction; i >= 0 && i < rows.count; i += direction)
      if (window.isSelectable(i)) return i
    return -1
  }

  function select(index) {
    if (index !== window.selectedIndex) {
      var previous = list.itemAtIndex(window.selectedIndex)
      if (previous) previous.selected = false
    }
    window.selectedIndex = index
    var current = list.itemAtIndex(index)
    if (current) current.selected = true
    window.selectedRow = Rows.snapshot(rows, index)
    // Argument values belong to one command; a different row starts empty.
    var id = window.selectedRow ? window.selectedRow.itemId : ""
    if (id !== window.argsForId) {
      window.argsForId = id
      window.argValues = ({})
      window.argFocus = -1
    }
    window.argDefs = window.selectedRow && window.selectedRow.argsJson ? JSON.parse(window.selectedRow.argsJson) : []
    if (index >= 0) list.positionViewAtIndex(index, ListView.Contain)
    if (index === window.nextSelectable(-1, 1)) list.positionViewAtBeginning()
  }

  function move(delta) {
    pointerGate.reset()
    if (window.selectedIndex < 0) { window.select(window.nextSelectable(-1, 1)); return }
    var step = delta > 0 ? 1 : -1
    var target = window.selectedIndex
    for (var n = 0; n < Math.abs(delta); n++) {
      var next = window.nextSelectable(target, step)
      if (next < 0) break
      target = next
    }
    window.select(target)
  }

  function jumpSection(direction) {
    var i = window.selectedIndex
    for (i += direction; i >= 0 && i < rows.count; i += direction)
      if (rows.get(i).rowKind === "section") break
    if (direction < 0) {
      for (i -= 1; i >= 0; i--) if (rows.get(i).rowKind === "section") break
    }
    var first = window.nextSelectable(Math.max(-1, i), 1)
    if (first >= 0) window.select(first)
  }

  function nthItem(n) {
    var seen = 0
    for (var i = 0; i < rows.count; i++) {
      if (!window.isSelectable(i)) continue
      if (++seen === n) return i
    }
    return -1
  }


  function actionsForSelected() {
    if (window.searchPending || !window.selectedRow) return []
    var r = window.backend.callSync("rootSearch.getActions", { id: window.selectedRow.itemId })
    return r.ok ? r.data : []
  }

  function perform(actionId, index) {
    if (window.searchPending) return
    if (index !== undefined && index >= 0) window.select(index)
    if (!window.selectedRow) return
    // Keyboard Shortcuts rows only show a key; Enter there does nothing.
    if (/^shortcut:/.test(window.selectedRow.itemId)) return
    window.actionPanelOpen = false
    // ↵ on a command with an empty required argument focuses that pill.
    if (actionId === "open" && window.argDefs.length) {
      var missing = RootSearch.missingArgument(window.argDefs, window.argValues)
      if (missing >= 0) { window.argFocus = missing; return }
    }
    window.request({ id: window.selectedRow.itemId, action: actionId, query: window.query, arguments: window.argValues })
  }

  function request(payload) {
    var r = window.backend.callSync("rootSearch.performAction", payload)
    if (!r.ok) { window.showToast("failure", r.error); return }
    var outcome = r.data || {}
    if (outcome.confirm) {
      var spec = outcome.confirm
      window.alert = { spec: { title: window.tr(spec.title), message: window.tr(spec.message), primary: window.tr(spec.primary), destructive: spec.destructive }, payload: payload }
      return
    }
    if (outcome.push) { window.push(outcome.push); return }
    if (outcome.close) {
      if (outcome.hud) window.hud(outcome.hud)
      window.dismissRequested()
      window.argValues = ({})
      window.argFocus = -1
      if (window.atRoot) window.setQuery("")
      return
    }
    if (outcome.toast) window.showToast(outcome.toast.style, outcome.toast.title, outcome.toast.actions)
    window.rebuild(false)
  }

  function confirmAlert() {
    var payload = Object.assign({}, window.alert.payload, { confirmed: true })
    window.alert = null
    window.request(payload)
  }

  function performNth(n) {
    var list = window.actionsForSelected()
    if (list.length > n) window.perform(list[n].id)
  }

  function performIfOffered(actionIds) {
    var list = window.actionsForSelected()
    for (var i = 0; i < list.length; i++) if (actionIds.indexOf(list[i].id) >= 0) { window.perform(list[i].id); return true }
    return false
  }

  function toggleActionPanel() {
    if (window.actionPanelOpen) { window.actionPanelOpen = false; return }
    // Titles in the user's language; ids and shortcuts stay as they are.
    window.actions = window.actionsForSelected().map(function(a) {
      var copy = ({})
      for (var k in a) copy[k] = a[k]
      copy.title = window.tr(a.title)
      return copy
    })
    window.actionPanelOpen = window.actions.length > 0
    if (actionPanel.item) actionPanel.item.filter = ""
  }

  function toggleDropdown() {
    if (window.dropdownOpen || !window.atRoot) { window.dropdownOpen = false; return }
    window.dropdownOpen = true
    dropdown.item.filter = ""
    var at = RootSearch.FILTERS.map(function(f) { return f.id }).indexOf(window.rootFilter)
    dropdown.item.selectedIndex = Math.max(0, at)
  }

  function setRootFilter(id) {
    window.dropdownOpen = false
    if (window.rootFilter === id) return
    window.rootFilter = id
    window.rebuild(true)
  }

  function toggleAbout() {
    if (window.aboutOpen || !window.selectedRow) { window.aboutOpen = false; return }
    var r = window.backend.callSync("rootSearch.getItemInfo", { id: window.selectedRow.itemId, query: window.query })
    if (!r.ok) { window.showToast("failure", r.error); return }
    window.aboutRows = (r.data || []).map(function(row) { return { label: window.tr(row.label), value: row.label === "Type" || row.label === "Saved" || row.label === "Last Opened" ? window.backend.trLabel(row.value) : row.value } })
    window.aboutOpen = r.data.length > 0
  }

  function toggleToastPanel() {
    if (window.toastPanelOpen) { window.toastPanelOpen = false; toastTimer.restart(); return }
    if (!window.toast || !window.toast.actions.length) return
    window.toastPanelOpen = true
    toastPanel.item.filter = ""
    toastTimer.stop()
  }

  // A toast action is a copy or a backend call (Backend.performAction's
  // toast.actions), with `done` as the success toast.
  function runToastAction(actionId) {
    var action = (window.toast ? window.toast.actions : []).filter(function(a) { return a.id === actionId })[0]
    window.toastPanelOpen = false
    if (!action) return
    if (action.copy !== undefined) {
      window.backend.copyText(action.copy)
      window.showToast("success", "Copied to Clipboard")
      return
    }
    var r = window.backend.callSync(action.call.method, action.call.data)
    if (!r.ok) { window.showToast("failure", r.error); return }
    window.toast = null
    window.rebuild(false)
    if (action.done) window.showToast("success", action.done)
  }

  // Typing, Tab and Backspace while an argument pill has focus.
  function handleArgumentKey(event, shift) {
    var def = window.argDefs[window.argFocus]
    var value = window.argValues[def.name] || ""
    var key = event.key
    function set(next) {
      var values = Object.assign({}, window.argValues)
      values[def.name] = next
      window.argValues = values
    }
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
      var step = shift || key === Qt.Key_Backtab ? -1 : 1
      var next = window.argFocus + step
      window.argFocus = next >= window.argDefs.length ? 0 : next
      return true
    }
    if (key === Qt.Key_Backspace && !value) { window.argFocus--; return true }
    if (Util.editsFilter(event, value)) { set(Util.editedFilter(event, value)); return true }
    if (window.isTyping(event)) { set(value + event.text); return true }
    return false
  }

  function saveAlias() {
    var r = window.backend.callSync("settings.updateCommandSettings", { commandId: window.view.commandId, alias: window.query })
    if (!r.ok) { window.showToast("failure", r.error); return }
    var saved = window.query.trim()
    window.pop()
    window.showToast("success", saved ? "Alias saved" : "Alias removed")
    window.rebuild(false)
  }


  // A failure toast always offers its message to copy (Ctrl+T).
  function showToast(style, title, actions) {
    var list = (actions || []).slice()
    if (style === "failure") list.push({ id: "copy-error", title: "Copy Error Message", copy: String(title || "") })
    window.toastPanelOpen = false
    window.toast = { style: style, title: String(title || ""), actions: list }
    toastTimer.interval = list.length ? 6000 : 2500
    toastTimer.restart()
    // Omarchy's windows have no status line; feedback is the shell's OSD,
    // which draws over the launcher without taking the keyboard. The toast
    // stays live for Ctrl+T, so the OSD names its first action. [D 2026-11-09]
    var message = window.backend.trLabel(String(title || ""))
    if (list.length) message += "  ·  Ctrl + T: " + window.tr(list[0].title)
    window.osd(style === "failure" ? "\uf071" : "\uf00c", message, toastTimer.interval)
  }

  Timer {
    id: toastTimer
    interval: 2500
    onTriggered: if (!window.toastPanelOpen) window.toast = null
  }

  function hud(text) {
    window.osd("\uf00c", window.backend.trLabel(String(text)), 1500)
  }

  // Omarchy's OSD. Plugins may not summon another plugin, so the request
  // goes to the shell's own IPC socket the way the omarchy-shell CLI sends
  // it (fields split by \x1f, ended by \x1e), but on stdin, so a message
  // never appears in a process's arguments (rule 6 in CLAUDE.md). JSON
  // escapes any control character in the message. [D 2026-11-09]
  function osd(icon, message, duration) {
    var request = ["osd", "show", JSON.stringify({ icon: icon, message: String(message), duration: duration })].join("\u001f") + "\u001e"
    if (osdProc.running) { osdProc.queued = request; return }
    osdProc.request = request
    osdProc.stdinEnabled = true
    osdProc.running = true
  }

  Process {
    id: osdProc
    property string request: ""
    property string queued: ""
    // Constant script: the socket name is worked out as omarchy-shell does.
    command: ["bash", "-c", 'id=$(printf "%s\\n%s" "$OMARCHY_PATH/shell" "${WAYLAND_DISPLAY:-}" | md5sum); sock="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-shell-${id:0:16}.sock"; [[ -S $sock ]] || exit 1; exec timeout 2s socat -t 2 - "UNIX-CONNECT:$sock" >/dev/null']
    onStarted: {
      write(osdProc.request)
      osdProc.request = ""
      osdProc.stdinEnabled = false
    }
    onExited: {
      if (!osdProc.queued) return
      osdProc.request = osdProc.queued
      osdProc.queued = ""
      osdProc.stdinEnabled = true
      osdProc.running = true
    }
  }


  function setQuery(next) {
    if (window.query === next) return
    window.query = next
    window.historyIndex = -1
    window.rebuild(true)
  }

  function pasteClipboard() {
    clipboardInput.clear()
    clipboardInput.paste()
    var text = clipboardInput.text.replace(/[\r\n\u2028\u2029]+/g, " ")
    clipboardInput.clear()
    if (!text) return
    if (window.actionPanelOpen) actionPanel.item.filter += text
    else if (window.argFocus >= 0) {
      var name = window.argDefs[window.argFocus].name
      var values = Object.assign({}, window.argValues)
      values[name] = (values[name] || "") + text
      window.argValues = values
    } else {
      if (window.view.kind === "alias") text = text.replace(/\s/g, "")
      window.setQuery(window.query + text)
    }
  }

  TextEdit {
    id: clipboardInput
    visible: false
    textFormat: TextEdit.PlainText
  }

  function recallHistory(direction) {
    var r = window.backend.callSync("rootSearch.getSearchHistory", null)
    var history = r.ok ? r.data : []
    if (history.length === 0) return false
    var next = Math.max(-1, Math.min(history.length - 1, window.historyIndex + direction))
    if (next === window.historyIndex) return true
    window.query = next < 0 ? "" : history[next]
    window.rebuild(true)
    window.historyIndex = next
    return true
  }

  function setZoom(value) {
    var z = Math.round(Math.max(0.8, Math.min(1.5, value)) * 10) / 10
    window.backend.callSync("settings.updateGeneralSettings", { uiZoom: z })
  }

  function handleEscape(shift) {
    if (window.alert) { window.alert = null; return }
    if (window.aboutOpen) { window.aboutOpen = false; return }
    if (window.dropdownOpen) { window.dropdownOpen = false; return }
    if (window.toastPanelOpen) { window.toggleToastPanel(); return }
    if (window.actionPanelOpen) { window.actionPanelOpen = false; return }
    if (window.argFocus >= 0 && !shift) { window.argFocus = -1; return }
    if (shift) { window.popToRoot(); return }
    if (window.general.escapeKeyBehavior === "close-and-pop-to-root") {
      window.dismissRequested()
      window.popToRoot()
      return
    }
    if (window.query && window.view.kind !== "alias") window.setQuery("")
    else if (!window.atRoot) window.pop()
    else window.dismissRequested()
  }

  // -1 up, 1 down or 0, per the navigation bindings. Ctrl+P only moves up
  // inside popups: in the list it opens the dropdown.
  function direction(event, ctrl, alt, inPopup) {
    var key = event.key
    if (!ctrl && !alt && key === Qt.Key_Down) return 1
    if (!ctrl && !alt && key === Qt.Key_Up) return -1
    if (!ctrl || alt || (event.modifiers & Qt.ShiftModifier)) return 0
    if (window.vim) return key === Qt.Key_J ? 1 : (key === Qt.Key_K ? -1 : 0)
    return key === Qt.Key_N ? 1 : (key === Qt.Key_P && inPopup ? -1 : 0)
  }

  function isActionPanelKey(ctrl, alt, shift, key) {
    if (key !== Qt.Key_K || shift) return false
    return window.vim ? alt && !ctrl : ctrl && !alt
  }

  // Keys for a popup list (action panel, dropdown, toast actions).
  function handlePopupKey(event, panel, ctrl, alt) {
    var dir = window.direction(event, ctrl, alt, true)
    if (dir) { panel.move(dir); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { panel.activateSelected(); return true }
    if (Util.editsFilter(event, panel.filter)) { panel.filter = Util.editedFilter(event, panel.filter); return true }
    if (window.isTyping(event)) { panel.filter += event.text; return true }
    return true
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var key = event.key
    var enter = key === Qt.Key_Return || key === Qt.Key_Enter

    if (window.alert) {
      if (key === Qt.Key_Escape) window.alert = null
      else if (enter) window.confirmAlert()
      return true
    }
    if (key === Qt.Key_Escape) { window.handleEscape(shift); return true }
    if (ctrl && (key === Qt.Key_Plus || key === Qt.Key_Equal)) { window.setZoom(window.zoom + 0.1); return true }
    if (ctrl && key === Qt.Key_Minus) { window.setZoom(window.zoom - 0.1); return true }
    if (ctrl && key === Qt.Key_0) { window.setZoom(1); return true }
    if (ctrl && key === Qt.Key_BracketLeft) { window.closePopups(); window.pop(); return true }
    // Ctrl+V, Ctrl+Shift+V (the terminal habit) and Shift+Insert paste.
    var meta = (event.modifiers & Qt.MetaModifier) !== 0
    if ((key === Qt.Key_V && ctrl && !alt && !meta) || (key === Qt.Key_Insert && shift && !ctrl && !alt && !meta)) {
      window.pasteClipboard()
      return true
    }

    if (window.aboutOpen) {
      if (ctrl && shift && key === Qt.Key_K) window.aboutOpen = false
      return true
    }
    if (window.dropdownOpen) {
      if (ctrl && !shift && key === Qt.Key_P) { window.dropdownOpen = false; return true }
      return window.handlePopupKey(event, dropdown.item, ctrl, alt)
    }
    if (window.toastPanelOpen) {
      if (ctrl && key === Qt.Key_T) { window.toggleToastPanel(); return true }
      return window.handlePopupKey(event, toastPanel.item, ctrl, alt)
    }
    if (window.actionPanelOpen) {
      if (window.isActionPanelKey(ctrl, alt, shift, key)) { window.actionPanelOpen = false; return true }
      return window.handlePopupKey(event, actionPanel.item, ctrl, alt)
    }

    if (window.view.kind === "alias") {
      if (enter) { window.saveAlias(); return true }
      if (key === Qt.Key_Space) return true
    } else {
      if (ctrl && shift && key === Qt.Key_K) { window.toggleAbout(); return true }
      if (window.isActionPanelKey(ctrl, alt, shift, key)) { window.toggleActionPanel(); return true }
      if (ctrl && !shift && key === Qt.Key_P) { window.toggleDropdown(); return true }
      if (ctrl && !shift && key === Qt.Key_T) { window.toggleToastPanel(); return true }
      // Shift+Enter opens a new window for apps; Enter focuses an open one.
      if (enter && shift && !ctrl && !alt && window.performIfOffered(["open-new"])) return true
      if (enter && ctrl && shift) { window.performNth(2); return true }
      if (enter && ctrl) { window.performNth(1); return true }
      if (enter) { window.performNth(0); return true }
      if (window.argFocus >= 0 && window.handleArgumentKey(event, shift)) return true
      if (key === Qt.Key_Tab && window.argDefs.length) { window.argFocus = 0; return true }
      if (ctrl && alt && key === Qt.Key_Up) { window.performIfOffered(["favorite-up"]); return true }
      if (ctrl && alt && key === Qt.Key_Down) { window.performIfOffered(["favorite-down"]); return true }
      if (ctrl && key === Qt.Key_Up) { window.jumpSection(-1); return true }
      if (ctrl && key === Qt.Key_Down) { window.jumpSection(1); return true }
      var dir = window.direction(event, ctrl, alt, false)
      if (dir < 0) {
        if (window.atRoot && (window.query === "" || window.historyIndex >= 0) && window.selectedIndex === window.nextSelectable(-1, 1) && window.recallHistory(1)) return true
        window.move(-1); return true
      }
      if (dir > 0) {
        if (window.historyIndex >= 0) { window.recallHistory(-1); return true }
        window.move(1); return true
      }
      if (key === Qt.Key_PageUp) { window.move(-8); return true }
      if (key === Qt.Key_PageDown) { window.move(8); return true }
      if (ctrl && shift && key === Qt.Key_F) { window.performIfOffered(["favorite-add", "favorite-remove"]); return true }
      if (ctrl && shift && key === Qt.Key_C) { window.performIfOffered(["copy-command", "copy-id", "copy-question-answer"]); return true }
      if (ctrl && shift && key === Qt.Key_D) { window.performIfOffered(["delete-all-entries"]); return true }
      if (ctrl && key === Qt.Key_D) { window.performIfOffered(["delete-entry"]); return true }
      if (alt && shift && key === Qt.Key_D) { window.performIfOffered(["disable"]); return true }
      if (ctrl && key >= Qt.Key_1 && key <= Qt.Key_9) {
        var target = window.nthItem(key - Qt.Key_0)
        if (target >= 0) window.perform("open", target)
        return true
      }
    }

    // ? on an empty search shows every shortcut, as ? does in Omarchy's
    // apps. Views where you type a name or path keep ? as text. [D 2026-11-09]
    if (event.text === "?" && !window.query && window.argFocus < 0
        && ["shortcuts", "alias"].indexOf(window.view.kind) < 0) {
      window.push({ kind: "shortcuts", title: "Keyboard Shortcuts" })
      return true
    }
    if (Util.editsFilter(event, window.query)) { window.setQuery(Util.editedFilter(event, window.query)); return true }
    if (key === Qt.Key_Backspace && !window.query && !window.atRoot) { window.pop(); return true }
    if (window.isTyping(event)) { window.setQuery(window.query + event.text); return true }
    return false
  }

  function isTyping(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
  }

  Connections {
    target: window.backend
    function onCandidatesRevisionChanged() { if (window.shown && !window.actionPanelOpen && !window.alert) window.rebuild(false) }
    // Exchange rates or zone offsets arrived: re-evaluate a calculation on screen.
    function onCalculatorRevisionChanged() { if (window.shown && !window.actionPanelOpen && window.query) window.rebuild(false) }
    // A language switch under Setup > Language re-renders the rows live.
    function onLanguageChanged() { if (window.shown) window.rebuild(true) }
    function onCatalogChanged() { if (window.shown) window.rebuild(true) }
  }


  // Omarchy's dim layer behind every menu-style card (menu.scrim).
  Rectangle {
    anchors.fill: parent
    color: window.look.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (!window.backend.config.keepVisibleOnFocusLoss) window.dismissRequested()
  }

  BorderSurface {
    id: card
    width: window.cardWidth
    height: window.compact ? window.headerHeight + card.contentTopInset + card.contentBottomInset : window.fullHeight
    radius: window.look.radius
    anchors.horizontalCenter: parent.horizontalCenter
    // Centred, as Omarchy's cards open. Compact mode keeps the full card's
    // top line, so the first keystroke grows it downward instead of
    // re-centring it (Menu.qml freezes its top for the same reason). [D]
    y: Math.max(Style.gapsOut, Math.round((window.height - window.fullHeight) / 2))
    color: window.look.background
    borderSpec: window.borderSpec
    padding: window.contentMargin
    clip: true

    MouseArea { anchors.fill: parent; onClicked: { window.closePopups(); keyCatcher.forceActiveFocus() } }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { if (window.handleKey(event)) event.accepted = true }
    }

    // The search line: plain text at the heading size, a dimmed placeholder,
    // no field chrome, no caret and no divider, like Omarchy's "Go…" line.
    Item {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: card.contentTopInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      height: window.headerHeight

      // Pushed views lead with Omarchy's submenu chevron, pointing back.
      Item {
        id: lead
        visible: !window.atRoot
        width: visible ? backGlyph.implicitWidth + window.px(10) : 0
        height: parent.height
        anchors.left: parent.left

        Text {
          id: backGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Commons.I18n.rightToLeft ? "›" : "‹"
          color: window.look.foreground
          opacity: 0.58
          font.family: window.look.fontFamily
          font.pixelSize: Math.round(Style.font.heading * window.zoom)
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: window.pop()
        }
      }

      // Room left of the filter button; argument pills sit right after the
      // typed text (ref 04 §2.2 WidthSizer).
      readonly property real queryRoom: (filterButton.visible ? filterButton.x - window.px(12) : headerStatus.visible ? headerStatus.x - window.px(12) : header.width) - queryText.x

      Text {
        id: queryText
        textFormat: Text.PlainText
        x: lead.width
        width: Math.min(implicitWidth, header.queryRoom - (pills.visible ? pills.width + window.px(10) : 0))
        anchors.verticalCenter: parent.verticalCenter
        text: window.query || (pills.visible ? "" : window.placeholder)
        color: window.look.foreground
        opacity: window.query ? 1 : 0.58
        font.family: window.look.fontFamily
        font.pixelSize: Math.round(Style.font.heading * window.zoom)
        elide: Text.ElideLeft
      }

      Row {
        id: pills
        visible: window.argDefs.length > 0 && window.view.kind !== "alias"
        x: queryText.x + (window.query ? queryText.width : 0) + window.px(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: window.px(6)

        Repeater {
          model: pills.visible ? window.argDefs : []

          // An argument is an Omarchy text control: normal fill and border,
          // the focus colour while it takes the typing.
          BorderSurface {
            id: pill
            required property var modelData
            required property int index
            readonly property string value: window.argValues[modelData.name] || ""
            readonly property bool focused: window.argFocus === index
            height: window.px(26)
            width: Math.min(window.px(220), pillText.implicitWidth + window.px(20))
            radius: Math.min(4, window.look.radius)
            color: Style.controlFill(pill.focused, false, window.look.foreground, window.look.accent)
            borderSpec: pill.focused ? Border.flat(window.look.selectedText, Style.normalBorderWidth) : Border.controlSpec("normal", window.look.foreground, window.look.accent)

            Text {
              id: pillText
              anchors.left: parent.left
              anchors.leftMargin: window.px(10)
              anchors.right: parent.right
              anchors.rightMargin: window.px(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: pill.value || (pill.modelData.placeholder + (pill.modelData.required ? "" : " (optional)"))
              opacity: pill.value ? 1 : 0.58
              color: window.look.foreground
              elide: Text.ElideLeft
              font.family: window.look.fontFamily
              font.pixelSize: Math.round(Style.font.body * window.zoom)
            }

            Rectangle {
              visible: pill.focused && window.shown
              width: Math.max(1, Style.space(2))
              height: pillText.font.pixelSize + Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              x: pillText.x + (pill.value ? Math.min(pillText.contentWidth, pillText.width) + Style.space(1) : 0)
              color: window.look.selectedText
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.IBeamCursor
              onClicked: { window.argFocus = pill.index; keyCatcher.forceActiveFocus() }
            }
          }
        }
      }

      // Slow work says so at the end of the search line (after 500 ms).
      Text {
        id: headerStatus
        visible: !filterButton.visible && text.length > 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: window.loadingVisible ? window.tr("Loading…") : ""
        color: window.look.foreground
        opacity: 0.52
        font.family: window.look.fontFamily
        font.pixelSize: Math.round(Style.font.bodySmall * window.zoom)
      }

      // The root filter is Omarchy's Dropdown trigger: control fill and
      // border, the 󰅀 chevron. Omarchy's search line carries nothing else,
      // so it only shows while a filter is on or its list is open (Ctrl+P).
      BorderSurface {
        id: filterButton
        visible: window.atRoot && !window.compact && (window.rootFilter !== "all" || window.dropdownOpen)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: window.px(26)
        width: filterRow.implicitWidth + Math.round(Style.spacing.controlPaddingX * 2 * window.zoom)
        radius: Math.min(4, window.look.radius)
        color: Style.controlFill(window.dropdownOpen, false, window.look.foreground, window.look.accent)
        borderSpec: Border.controlSpec(window.dropdownOpen ? "focus" : "normal", window.look.foreground, window.look.accent)

        Row {
          id: filterRow
          anchors.centerIn: parent
          spacing: Math.round(Style.spacing.controlGap * window.zoom)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: window.tr((RootSearch.FILTERS.filter(function(f) { return f.id === window.rootFilter })[0] || RootSearch.FILTERS[0]).title)
            color: window.look.foreground
            opacity: window.rootFilter === "all" ? 0.7 : 1
            font.family: window.look.fontFamily
            font.pixelSize: Math.round(Style.font.body * window.zoom)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰅀"
            color: Qt.darker(window.look.foreground, 1.2)
            font.family: window.look.fontFamily
            font.pixelSize: Math.round(Style.font.body * window.zoom)
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { window.toggleDropdown(); keyCatcher.forceActiveFocus() }
        }
      }
    }

    Item {
      id: body
      visible: !window.compact
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: header.bottom
      anchors.topMargin: window.contentSpacing
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset

      ListView {
        id: list
        anchors.fill: parent
        visible: window.view.kind !== "alias"
        clip: true
        model: rows
        spacing: Math.round(Style.spacing.xs * window.zoom)
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds

        delegate: ResultRow {
          Component.onCompleted: selected = index === window.selectedIndex
          ListView.onReused: selected = index === window.selectedIndex
          ListView.onPooled: selected = false
          searching: window.query.length > 0
          look: window.look
          appLibrary: window.appLibrary
          zoom: window.zoom
          onHovered: function(i, item, mouse) { if (!window.actionPanelOpen && pointerGate.moved(item, mouse)) window.select(i) }
          onClicked: function(i) { window.perform("open", i) }
        }
      }

      // Omarchy's scroll scrims: each edge fades by how much is hidden past it.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(window.px(28), parent.height / 2)
        visible: list.visible && opacity > 0
        opacity: list.contentHeight > list.height ? Math.max(0, Math.min(1, (list.contentY - list.originY) / height)) : 0
        gradient: Gradient {
          GradientStop { position: 0; color: window.look.background }
          GradientStop { position: 1; color: Util.alpha(window.look.background, 0) }
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(window.px(28), parent.height / 2)
        visible: list.visible && opacity > 0
        opacity: list.contentHeight > list.height ? Math.max(0, Math.min(1, (list.originY + list.contentHeight - list.height - list.contentY) / height)) : 0
        gradient: Gradient {
          GradientStop { position: 0; color: Util.alpha(window.look.background, 0) }
          GradientStop { position: 1; color: window.look.background }
        }
      }

      // Empty states in Omarchy's form: a large glyph in the selected-text
      // colour, then the message.
      Column {
        anchors.centerIn: parent
        width: parent.width - window.contentMargin * 2
        spacing: window.px(8)
        visible: window.view.kind === "alias" || rows.count === 0

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: window.view.kind === "alias" ? "" : "󰈉"
          color: window.look.selectedText
          opacity: 0.8
          font.family: window.look.fontFamily
          font.pixelSize: Math.round(Style.font.displayLarge * window.zoom)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: window.view.kind === "alias" ? window.view.title
            : window.view.kind === "calculator-history" && !window.query ? window.tr("No Calculations Yet")
            : (window.backend.ready ? (window.query ? window.tr("No matches for %1").arg(window.query) : window.tr("No results")) : window.tr("Loading…"))
          color: window.look.foreground
          opacity: 0.7
          elide: Text.ElideRight
          font.family: window.look.fontFamily
          font.pixelSize: Math.round(Style.font.title * window.zoom)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: window.view.kind === "alias" ? window.tr("Typing the alias exactly in the root search puts this command on top. Leave it empty to remove it.")
            : window.view.kind === "calculator-history" && !window.query ? window.tr("Type a calculation in the root search, then copy or paste the answer.")
            : ""
          visible: text.length > 0
          color: window.look.foreground
          opacity: 0.52
          font.family: window.look.fontFamily
          font.pixelSize: Math.round(Style.font.bodySmall * window.zoom)
        }
      }
    }

    Loader {
      id: actionPanel
      active: window.actionPanelOpen
      z: 10
      anchors.right: parent.right
      anchors.rightMargin: card.contentRightInset
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.contentBottomInset
      sourceComponent: ActionPanel {
        placeholder: window.tr("Search for actions…")
        actions: window.actions
        look: window.look
        zoom: window.zoom
        onActivated: function(actionId) { window.perform(actionId) }
      }
    }

    Loader {
      id: dropdown
      active: window.dropdownOpen
      z: 10
      width: window.px(240)
      anchors.right: parent.right
      anchors.rightMargin: card.contentRightInset
      anchors.top: header.bottom
      anchors.topMargin: window.contentSpacing
      sourceComponent: ActionPanel {
        placeholder: window.tr("Filter…")
        actions: RootSearch.FILTERS.map(function(f) {
          return { id: f.id, title: window.tr(f.title), shortcut: "", section: "filter", icon: f.id === window.rootFilter ? "✓" : " " }
        })
        look: window.look
        zoom: window.zoom
        onActivated: function(id) { window.setRootFilter(id) }
      }
    }

    Loader {
      id: toastPanel
      active: window.toastPanelOpen
      z: 10
      width: window.px(280)
      anchors.left: parent.left
      anchors.leftMargin: card.contentLeftInset
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.contentBottomInset
      sourceComponent: ActionPanel {
        placeholder: window.tr("Search toast actions…")
        actions: (window.toast ? window.toast.actions : []).map(function(a) {
          return { id: a.id, title: window.tr(a.title), shortcut: "", section: "toast", icon: " " }
        })
        look: window.look
        zoom: window.zoom
        onActivated: function(id) { window.runToastAction(id) }
      }
    }

    Loader {
      active: window.aboutOpen
      z: 10
      anchors.right: parent.right
      anchors.rightMargin: card.contentRightInset
      anchors.bottom: parent.bottom
      anchors.bottomMargin: card.contentBottomInset
      sourceComponent: InfoPanel {
        title: window.selectedRow ? window.selectedRow.title : ""
        rows: window.aboutRows
        look: window.look
        zoom: window.zoom
      }
    }

    Loader {
      active: !!window.alert
      z: 20
      anchors.fill: parent
      sourceComponent: Alert {
        spec: window.alert ? window.alert.spec : null
        cancelText: window.tr("Cancel")
        look: window.look
        zoom: window.zoom
        onConfirmed: window.confirmAlert()
        onCancelled: window.alert = null
      }
    }
  }
}
