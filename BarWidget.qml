import QtQuick
import QtQuick.Controls
import Quickshell
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
    text: root.labelText
    labelVisible: true
    hasVisualContent: root.labelText !== ""
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: function(b) {
      root.togglePanel()
    }
  }

  Process {
    id: proc
    command: ["bash", "-lc", String(root.setting("exec", "~/.local/bin/agx-cpu-ram-usage"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
  }

  Timer {
    interval: Math.max(1, Number(root.setting("interval", 5))) * 1000
    running: String(root.setting("exec", "~/.local/bin/agx-cpu-ram-usage")) !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
