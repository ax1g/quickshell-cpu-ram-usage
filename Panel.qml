import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Details popup for the cpu-ram bar widget: live CPU and memory meters plus
// the top memory consumers. Read-only — the panel mirrors the snapshot the
// bar widget polls from the agx-cpu-ram-usage script.
Panel {
  id: root
  moduleName: "agx.cpu-ram"

  property var anchorItem: null
  property var hostWidget: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — so the
  // popout coordinator and panel switching must identify us by that widget.
  readonly property var barIdentity: hostWidget || root

  // Live snapshot owned by the bar widget; the panel only reads it.
  readonly property var stats: hostWidget && hostWidget.stats ? hostWidget.stats : null

  // Guarded so the widget renders before the bar is injected.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cpuPercent: Model.cpuPercent(root.stats)
  readonly property int ramPercent: Model.pctFor(root.stats, "ram")
  readonly property bool hasSwap: Model.value(root.stats, "swap", "total_kb", 0) > 0
  readonly property var topApps: Model.topApps(root.stats)
  readonly property var others: Model.others(root.stats)
  // Header ties to system used so Top5 + Others sums to it exactly.
  readonly property string usedLabel: Model.fmtMemory(Model.value(root.stats, "ram", "used_kb", 0))
  readonly property string loadLabel: Model.loadLabel(root.stats)
  readonly property string tempLabel: Model.cpuTemp(root.stats)

  function open() {
    root.refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function scrollBy(dy) {
    var flick = panelScroll
    if (!flick || flick.contentHeight <= flick.height) return
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
  }

  function refresh() {
    if (root.hostWidget && typeof root.hostWidget.refresh === "function")
      root.hostWidget.refresh()
  }

  // b-key shortcut: drop the panel and open btop in a floating terminal,
  // matching how the network panel summons its tools.
  function openBtop() {
    root.close()
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("omarchy-launch-floating-terminal-with-presentation btop")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.scrollBy(-dy * Style.space(24))
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "g") panelScroll.contentY = 0
        else if (t === "G") panelScroll.contentY = Math.max(0, panelScroll.contentHeight - panelScroll.height)
        else if (t === "b" || t === "B") root.openBtop()
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: panelColumn.width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: panelColumn
          width: panelScroll.width
          spacing: Style.space(12)

          // ---- CPU ------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            ResourceHeader {
              icon: "󰍛"
              label: "CPU"
              value: root.cpuPercent + "%"
            }

            Meter {
              pct: root.cpuPercent
            }

            StatRow {
              label: "TEMP"
              value: root.tempLabel
            }

            StatRow {
              label: "LOAD"
              value: root.loadLabel
            }
          }

          // ---- RAM ------------------------------------------------------
          PanelSeparator {
            foreground: root.contentForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            ResourceHeader {
              icon: ""
              label: "RAM"
              value: root.ramPercent + "%"
            }

            Meter {
              pct: root.ramPercent
            }

            StatRow {
              label: "USED"
              value: Model.fmtMemory(Model.value(root.stats, "ram", "used_kb", 0))
            }

            StatRow {
              label: "AVAILABLE"
              value: Model.fmtMemory(Model.value(root.stats, "ram", "available_kb", 0))
            }

            StatRow {
              label: "TOTAL"
              value: Model.fmtMemory(Model.value(root.stats, "ram", "total_kb", 0))
            }

            StatRow {
              visible: root.hasSwap
              label: "SWAP"
              value: Model.fmtMemory(Model.value(root.stats, "swap", "used_kb", 0))
            }
          }

          // ---- Top memory consumers -------------------------------------
          Column {
            visible: root.topApps.length > 0 || root.others !== null
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator {
              visible: parent.visible
              foreground: root.contentForeground
            }

            SectionHeader {
              label: "TOP MEMORY"
              value: root.usedLabel
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Repeater {
                model: root.topApps

                // Two-column rows, same look as the network panel's info grid:
                // dimmed label on the left, right-aligned value on the right,
                // bodySmall text, labelGap row spacing, Space(20) column gap.
                Item {
                  required property var modelData

                  readonly property string appName: String(modelData.name || "")
                  readonly property string memLabel: String(modelData.label || "")

                  width: parent.width
                  implicitHeight: Math.max(appNameText.implicitHeight, appMemText.implicitHeight)

                  InfoLabel {
                    id: appNameText
                    text: appName
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.right: appMemText.left
                    anchors.rightMargin: Style.space(20)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  InfoValue {
                    id: appMemText
                    text: memLabel
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }

              // Remainder row: everything outside the top 5 plus kernel-side
              // usage, so the rows sum to the header (system used) exactly.
              Item {
                visible: root.others !== null
                width: parent.width
                implicitHeight: Math.max(othersNameText.implicitHeight, othersMemText.implicitHeight)

                InfoLabel {
                  id: othersNameText
                  text: root.others ? root.others.name : ""
                  elide: Text.ElideRight
                  anchors.left: parent.left
                  anchors.right: othersMemText.left
                  anchors.rightMargin: Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                }

                InfoValue {
                  id: othersMemText
                  text: root.others ? root.others.label : ""
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // Keyboard hint, styled like the section header values (dim caption)
          // so it reads as a footer rather than a data row.
          Text {
            width: parent.width
            text: "b \u00b7 open btop"
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }

          Item {
            width: parent.width
            height: Style.space(2)
          }
        }
      }
    }
  }

  // Resource header: resource glyph + name with a right-aligned percentage,
  // sized like the old hero (display icon, title text).
  component ResourceHeader: Item {
    required property string icon
    required property string label
    required property string value

    width: parent.width
    implicitHeight: Math.max(resIcon.implicitHeight, resLabel.implicitHeight)

    Text {
      id: resIcon
      text: icon
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.display
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: resLabel
      text: label
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      anchors.left: resIcon.right
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    Text {
      id: resValue
      text: value
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
  }

  // Section header: small-caps label with a right-aligned value ("CPU USAGE" · "12%").
  component SectionHeader: Item {
    required property string label
    required property string value

    width: parent.width
    implicitHeight: Math.max(headerLabel.implicitHeight, headerValue.implicitHeight)

    PanelSectionHeader {
      id: headerLabel
      text: label
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: headerValue
      visible: value !== ""
      text: value
      color: Qt.darker(root.contentForeground, 1.4)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
  }

  // Stat row: dim label on the left, live value on the right.
  component StatRow: Item {
    required property string label
    required property string value

    width: parent.width
    implicitHeight: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

    Text {
      id: rowLabel
      text: label
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: rowValue
      text: value
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      width: parent.width * 0.62
      horizontalAlignment: Text.AlignRight
    }
  }

  // Progress meter: rounded track with an accent fill, animated like the
  // per-app bars in the screen-time panel.
  component Meter: Item {
    required property int pct

    readonly property int barHeight: Style.space(5)

    width: parent.width
    implicitHeight: barHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius > 0 ? height / 2 : 0
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

      Rectangle {
        width: Math.round(parent.width * (Math.max(0, Math.min(100, pct)) / 100))
        height: parent.height
        radius: parent.radius
        color: Style.selectedStateColor(root.contentForeground, Color.accent)

        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
    }
  }

  // Two-column info rows, mirroring the network panel's label/value pair:
  // dimmed small label, plain small value.
  component InfoLabel: Text {
    color: root.contentForeground
    opacity: 0.6
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
