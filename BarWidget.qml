import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget: CPU + memory usage with a click-to-open details popup. The
// agx-cpu-ram-usage script produces the bar label plus the live metrics
// (cpu/ram/swap/top apps); the widget renders the label and the panel
// mirrors the same snapshot.
BarWidget {
  id: root
  moduleName: "agx.cpu-ram"

  property string labelText: "--%"
  property var stats: ({})

  // Icon-only mode: right-clicking shrinks the widget to just the CPU glyph.
  // The state lives in the widget's shell.json entry ("iconOnly"), so it
  // survives restarts and follows the widget across bar slots.
  readonly property string cpuGlyph: "󰍛"
  readonly property string ramGlyph: ""
  readonly property bool iconOnly: {
    var v = root.setting("iconOnly", false)
    return v === true || v === "true"
  }

  // Vertical bar (left/right edge): the button's text label is hidden in
  // vertical mode, so the content is drawn as stacked OpticalGlyph lines —
  // CPU glyph, then the bodyText tokens (percent, RAM amount) with the RAM
  // glyph dropped since the stack already reads top-to-bottom. Same shape
  // as omarchy.clock's vertical stack.
  readonly property var verticalLines: {
    if (!root.vertical) return []
    var lines = [root.cpuGlyph]
    if (!root.iconOnly) {
      var toks = String(root.bodyText || "").split(/\s+/)
      for (var i = 0; i < toks.length; i++) {
        if (toks[i] && toks[i] !== root.ramGlyph) lines.push(toks[i])
      }
    }
    return lines
  }

  // The poll label minus the leading CPU glyph: " 16%  3.1GB". Kept
  // plain-text: WidgetButton renders with Text.PlainText, so any HTML
  // (e.g. a <span> enlarging the glyph) would leak literally onto the bar.
  // The glyph renders at body size, matching agx.screen-time's time mode.
  readonly property string bodyText: {
    var t = String(root.labelText || "")
    if (t.indexOf(root.cpuGlyph) === 0) t = t.slice(root.cpuGlyph.length)
    return t
  }
  readonly property bool hasLabel: String(root.labelText || "") !== ""

  function toggleIconOnly() {
    var next = !root.iconOnly
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.iconOnly = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // The poll command. Defaults to the bundled agx-cpu-ram-usage script; a
  // user "exec" setting overrides it (kept as a raw shell command string).
  readonly property string execCommand: {
    var s = String(root.setting("exec", ""))
    if (s) return s
    var u = Qt.resolvedUrl("agx-cpu-ram-usage").toString()
    return u.startsWith("file://") ? u.slice(7) : u
  }

  // The bar's open-panel indicator (underline) tracks the painted label
  // width instead of a fraction of the slot, mirroring omarchy.clock.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // ---- Panel shape contract for shell.summon/hide/toggle routing ---------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (proc.running) return
    if (root.bar && root.bar.runProcess) root.bar.runProcess(proc)
    else proc.running = true
  }

  function update(raw) {
    var data = Util.parseModuleJson(raw)
    if (data.text) root.labelText = String(data.text)
    if (data.tooltip) button.tooltipText = String(data.tooltip)
    root.stats = data
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "agx.cpu-ram"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function status(): void {
      var p = panelLoader.item
      console.log("agx.cpu-ram status: opened=" + (p ? p.opened : "no-panel")
        + " label=" + root.labelText)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : (root.iconOnly ? root.cpuGlyph : root.labelText)
    fontSize: root.vertical ? Style.font.body : (root.iconOnly ? Style.font.title : Style.font.body)
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : (root.hasLabel || root.iconOnly)
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleIconOnly()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData === root.cpuGlyph
            ? Style.font.icon
            : (modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize)
          color: button.foreground
        }
      }
    }
  }

  Process {
    id: proc
    command: ["bash", "-lc", root.execCommand]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
  }

  Timer {
    interval: Math.max(1, Number(root.setting("interval", 5))) * 1000
    running: root.execCommand !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
