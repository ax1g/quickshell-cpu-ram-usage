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
  // Collapsed shows the top 5; expanded unfolds the entire process list,
  // screen-time legend style. Reset by toggle so the list restarts at top.
  property bool expanded: false
  readonly property var topRows: Model.topApps(root.stats)
  readonly property var allRows: Model.allApps(root.stats)
  // Collapsed tail is Others (Top5 + Others == used); expanded tail is the
  // kernel remainder (every process already listed).
  readonly property var tailRow: root.expanded ? Model.kernelRow(root.stats) : Model.others(root.stats)
  readonly property var displayRows: root.tailRow ? (root.expanded ? root.allRows : root.topRows).concat([root.tailRow]) : (root.expanded ? root.allRows : root.topRows)
  readonly property int hiddenCount: Math.max(0, root.allRows.length - root.topRows.length)
  // Theme-aware rank palette off the theme accent; rows past the top 5
  // share the tail color, like screen-time's Other slice.
  readonly property var swatchColors: [
    Color.accent,
    Qt.darker(Color.accent, 1.25),
    Qt.lighter(Color.accent, 1.2),
    Qt.darker(Color.accent, 1.6),
    Qt.lighter(Color.accent, 1.4)
  ]
  readonly property color tailColor: Qt.darker(root.contentForeground, 1.4)
  // Header ties to system used so the collapsed rows sum to it exactly.
  readonly property string usedLabel: Model.fmtMemory(Model.value(root.stats, "ram", "used_kb", 0))
  readonly property string cpuSub: Model.cpuSub(root.stats)
  readonly property string ramSub: Model.ramSub(root.stats)
  readonly property string swapSub: Model.swapSub(root.stats)

  onExpandedChanged: appScroll.contentY = 0

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
        else if (t === "m" || t === "M") root.expanded = !root.expanded
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
            visible: root.displayRows.length > 0
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

            // Collapsed rows size naturally; expanded scrolls inside a fixed
            // box with a thin edge indicator, like screen-time's legend.
            Item {
              id: listBox
              width: parent.width
              height: root.expanded ? Math.min(appList.implicitHeight, Style.space(248)) : appList.implicitHeight

              Flickable {
                id: appScroll
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: appList.implicitHeight
                interactive: contentHeight > height
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                Column {
                  id: appList
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: root.displayRows

                    AppRow {
                      palette: root.swatchColors
                      tail: root.tailColor
                    }
                  }
                }
              }

              // Thin scrollbar indicator on the right edge.
              Rectangle {
                property real ratio: appScroll.contentHeight > 0 ? appScroll.height / appScroll.contentHeight : 0
                visible: appScroll.contentHeight > appScroll.height
                width: 2
                height: Math.max(Style.space(16), appScroll.height * ratio)
                radius: width / 2
                color: root.contentForeground
                opacity: 0.25
                anchors.right: appScroll.right
                y: appScroll.y + (appScroll.height - height) * (appScroll.contentHeight > appScroll.height ? appScroll.contentY / (appScroll.contentHeight - appScroll.height) : 0)
              }
            }

            // Show more/less footer, screen-time hero-corner style.
            Item {
              visible: root.hiddenCount > 0
              width: parent.width
              implicitHeight: Math.max(moreText.implicitHeight, moreChevron.implicitHeight)

              Text {
                id: moreText
                text: root.expanded ? "SHOW LESS" : "SHOW MORE (" + root.hiddenCount + ")"
                color: moreMouse.containsMouse ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                anchors.right: moreChevron.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: moreChevron
                text: root.expanded ? "\u25be" : "\u25b8"
                color: moreMouse.containsMouse ? root.contentForeground : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
              }
            }
          }

          // Keyboard hint, styled like the section header values (dim caption)
          // so it reads as a footer rather than a data row.
          Text {
            width: parent.width
            text: "m \u00b7 more   b \u00b7 open btop"
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
        color: Color.accent
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

  // App row: accent meter fill behind a swatch-dot row (name + value),
  // screen-time legend style. Top ranks take the theme palette; deeper
  // rows share the dim tail color.
  component AppRow: Item {
    required property var modelData
    required property int index
    required property var palette
    required property color tail

    readonly property string appName: String(modelData.name || "")
    readonly property string memLabel: String(modelData.label || "")
    readonly property real fillFrac: Math.max(0, Math.min(1, Number(modelData.frac) || 0))
    readonly property color swatchColor: index < 5 ? (palette[index] || tail) : tail

    width: parent.width
    implicitHeight: Math.max(rowNameText.implicitHeight, rowMemText.implicitHeight) + Style.space(6)

    Rectangle {
      id: rowFill
      width: Math.round(parent.width * fillFrac)
      height: parent.height
      radius: height / 3
      color: Color.accent
      opacity: 0.14

      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Rectangle {
      id: rowSwatch
      width: Style.space(7)
      height: width
      radius: width / 2
      color: swatchColor
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: rowNameText
      text: appName
      color: root.contentForeground
      opacity: 0.6
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: rowSwatch.right
      anchors.leftMargin: Style.space(6)
      anchors.right: rowMemText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: rowMemText
      text: memLabel
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
  }
}
