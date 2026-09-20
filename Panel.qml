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
  readonly property var topApps: Model.topApps(root.stats)
  readonly property var others: Model.others(root.stats)
  // Grid cells: top 5 plus the remainder, so the grid always fills complete
  // 2-column rows (5 + Others = 6).
  readonly property var memCells: root.others ? root.topApps.concat([root.others]) : root.topApps
  // Header ties to system used so Top5 + Others sums to it exactly.
  readonly property string usedLabel: Model.fmtMemory(Model.value(root.stats, "ram", "used_kb", 0))
  readonly property string cpuSub: Model.cpuSub(root.stats)
  readonly property string ramSub: Model.ramSub(root.stats)
  readonly property string swapSub: Model.swapSub(root.stats)

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
    contentWidth: panel.fittedContentWidth(Style.space(400))
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
          spacing: Style.space(8)

          // ---- CPU + RAM side by side ---------------------------------
          Row {
            width: parent.width
            spacing: Style.space(8)

            ResourceCard {
              icon: "󰍛"
              title: "CPU"
              value: root.cpuPercent + "%"
              pct: root.cpuPercent
              sub: root.cpuSub
              width: (parent.width - Style.space(8)) / 2
            }

            ResourceCard {
              icon: ""
              title: "RAM"
              value: root.ramPercent + "%"
              pct: root.ramPercent
              sub: root.ramSub
              sub2: root.swapSub
              width: (parent.width - Style.space(8)) / 2
            }
          }

          // ---- Top memory consumers -------------------------------------
          Column {
            visible: root.memCells.length > 0
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

            // Two-column grid: top 5 plus Others fills 3 complete rows.
            Grid {
              id: appGrid
              width: parent.width
              columns: 2
              rowSpacing: Style.spacing.labelGap
              columnSpacing: Style.space(20)

              readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

              Repeater {
                model: root.memCells

                // Compact two-column rows, same look as the network panel's
                // info grid: dimmed label left, right-aligned value right.
                Item {
                  required property var modelData

                  readonly property string appName: String(modelData.name || "")
                  readonly property string memLabel: String(modelData.label || "")

                  width: appGrid.cellWidth
                  implicitHeight: Math.max(cellNameText.implicitHeight, cellMemText.implicitHeight)

                  InfoLabel {
                    id: cellNameText
                    text: appName
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.right: cellMemText.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  InfoValue {
                    id: cellMemText
                    text: memLabel
                    horizontalAlignment: Text.AlignRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
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

  // Resource card: glyph + name with a right-aligned percentage, a meter,
  // then one or two dim sub-lines ("66°C · 1.8 1.4 1.3"). Two cards sit
  // side by side in the overview row.
  component ResourceCard: Column {
    required property string icon
    required property string title
    required property string value
    required property int pct
    required property string sub
    property string sub2: ""

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(cardIcon.implicitHeight, cardTitle.implicitHeight)

      Text {
        id: cardIcon
        text: icon
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: cardTitle
        text: title
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        anchors.left: cardIcon.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
      }

      Text {
        id: cardValue
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

    Meter {
      pct: parent.pct
    }

    Text {
      width: parent.width
      visible: parent.sub !== ""
      text: parent.sub
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: parent.sub2 !== ""
      text: parent.sub2
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
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
