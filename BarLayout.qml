import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons
import "I18n.js" as I18n

// Arranging the bar, by keyboard or by dragging.
//
// Omarchy can move and place bar widgets from the command line but shows the
// arrangement nowhere, so this is the view of it. The three columns are drawn
// the way the bar is laid out, left to right, because that is the thing being
// edited.
//
// The selection is tracked by widget id, never by position. Every edit reloads
// the layout from the shell, and after a move the indexes have all shifted, so
// a positional cursor would silently end up on a different widget than the one
// the user was looking at.
Item {
  id: barView

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  // Not `data`: that is Item's default property, the list holding a component's
  // own children. Declaring it shadows the children and the view renders
  // nothing, with no error from qmllint or the runtime.
  property var barData: null
  property bool busy: false

  // The widget under the cursor, by id.
  property string selectedId: ""

  signal moveWidget(string id, string section, int index)
  signal putWidget(string id, string section, int index)
  signal removeWidget(string id)
  signal revertLayout()

  readonly property var sections: barData && barData.sections ? barData.sections : []
  readonly property var available: barData && barData.available ? barData.available : []
  readonly property var order: ["left", "center", "right"]

  function widgetsIn(name) {
    for (var i = 0; i < sections.length; i++)
      if (sections[i].section === name)
        return sections[i].widgets
    return []
  }

  // Everything selectable, in reading order: the three columns top to bottom,
  // then the unplaced row. One flat list keeps cursor movement simple and
  // keeps "where am I" answerable by a single lookup.
  readonly property var flat: {
    var out = []
    for (var s = 0; s < order.length; s++) {
      var list = widgetsIn(order[s])
      for (var i = 0; i < list.length; i++)
        out.push({ id: list[i].id, section: order[s], index: i, placed: true, widget: list[i] })
    }
    for (var a = 0; a < available.length; a++)
      out.push({ id: available[a].id, section: "", index: a, placed: false, widget: available[a] })
    return out
  }

  function entryFor(id) {
    for (var i = 0; i < flat.length; i++)
      if (flat[i].id === id)
        return flat[i]
    return null
  }

  readonly property var current: selectedId === "" ? null : entryFor(selectedId)

  // Keep a selection alive across reloads. If the selected widget is gone,
  // fall back to the first thing there is rather than to nothing.
  onFlatChanged: {
    if (flat.length === 0) {
      selectedId = ""
      return
    }
    if (selectedId === "" || entryFor(selectedId) === null)
      selectedId = flat[0].id
  }

  // ── cursor ──────────────────────────────────────────────────────────────
  // Moves the highlight only. Never changes the bar.
  function moveCursor(dx, dy) {
    if (flat.length === 0)
      return
    var cur = current
    if (!cur) {
      selectedId = flat[0].id
      return
    }

    if (dy !== 0) {
      if (cur.placed) {
        var col = widgetsIn(cur.section)
        var t = cur.index + dy
        if (t >= 0 && t < col.length) {
          selectedId = col[t].id
          return
        }
        // Falling off the bottom of a column steps into the unplaced row.
        if (t >= col.length && available.length > 0) {
          selectedId = available[0].id
          return
        }
        return
      }
      if (dy < 0) {
        var back = widgetsIn("left")
        selectedId = back.length ? back[back.length - 1].id : flat[0].id
        return
      }
      var ni = Math.min(available.length - 1, cur.index + dy)
      selectedId = available[ni].id
      return
    }

    if (dx !== 0) {
      if (!cur.placed) {
        var na = Math.max(0, Math.min(available.length - 1, cur.index + dx))
        selectedId = available[na].id
        return
      }
      var si = order.indexOf(cur.section)
      var ns = Math.max(0, Math.min(order.length - 1, si + dx))
      if (ns === si)
        return
      var dest = widgetsIn(order[ns])
      if (dest.length === 0)
        return
      selectedId = dest[Math.min(cur.index, dest.length - 1)].id
    }
  }

  // ── moving the widget ───────────────────────────────────────────────────
  // Uppercase HJKL. The selection is by id, so it stays on the same widget
  // after the layout reloads and a run of presses keeps acting on it.
  function shiftSelected(dx, dy) {
    var cur = current
    if (!cur || barView.busy)
      return

    if (!cur.placed) {
      // Unplaced: any horizontal press drops it into that end of the bar.
      var target = dx < 0 ? "left" : dx > 0 ? "right" : "center"
      barView.putWidget(cur.id, target, widgetsIn(target).length)
      return
    }

    if (dx !== 0) {
      var si = order.indexOf(cur.section)
      var ns = Math.max(0, Math.min(order.length - 1, si + dx))
      if (ns === si)
        return
      barView.moveWidget(cur.id, order[ns], widgetsIn(order[ns]).length)
      return
    }

    if (dy !== 0) {
      var col = widgetsIn(cur.section)
      var to = cur.index + dy
      if (to < 0 || to >= col.length)
        return
      barView.moveWidget(cur.id, cur.section, to)
    }
  }

  function removeCursorWidget() {
    var cur = current
    if (!cur || !cur.placed || barView.busy)
      return
    barView.removeWidget(cur.id)
  }

  function activateCursor() {
    var cur = current
    if (!cur || barView.busy)
      return
    if (!cur.placed)
      barView.putWidget(cur.id, "right", widgetsIn("right").length)
  }

  // What is being dragged, so every drop area can ask about it.
  property string dragId: ""
  property bool dragPlaced: false

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(Color.popups.border, Style.normalBorderAlpha)
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.controlGap

      Text {
        text: barView.tr("Bar layout")
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        textFormat: Text.PlainText
      }

      Button {
        text: barView.tr("Undo my changes")
        tooltipText: barView.tr("Put the bar back the way it was when this view opened")
        fontSize: Style.font.caption
        enabled: !barView.busy
        onClicked: barView.revertLayout()
      }

      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        textFormat: Text.PlainText
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        text: barView.barData
          ? barView.tr("bar at the %1  ·  %2 placed  ·  %3 available",
            barView.tr(barView.barData.barPosition),
            barView.barData.counts.placed, barView.barData.counts.available)
          : ""
      }
    }

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      text: barView.tr("Drag a widget where you want it, or move the cursor with the arrows "
        + "and press uppercase H, J, K or L to move the widget itself. x takes "
        + "one off the bar.")
    }

    // ── the three sections, drawn as the bar is ──────────────────────────
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.spacing.controlGap

      Repeater {
        model: barView.sections
        delegate: SectionColumn {
          required property var modelData
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredWidth: 1
          section: modelData.section
          widgets: modelData.widgets
        }
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
      visible: barView.available.length > 0
    }

    // ── installed but not placed ─────────────────────────────────────────
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs
      visible: barView.available.length > 0

      Text {
        text: barView.tr("NOT ON THE BAR")
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.sm

        Repeater {
          model: barView.available
          delegate: WidgetRow {
            required property var modelData
            width: Math.min(Style.space(170), barView.width / 3)
            widget: modelData
            placed: false
          }
        }
      }
    }
  }

  // One bar section: a labelled column that accepts drops.
  component SectionColumn: ColumnLayout {
    id: col
    property string section: ""
    property var widgets: []

    spacing: Style.spacing.xxs

    Text {
      text: barView.tr(col.section.toUpperCase())
      color: dropArea.containsDrag ? Color.accent : Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      Layout.bottomMargin: Style.spacing.xxs
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: dropArea.containsDrag ? Util.alpha(Color.accent, 0.10) : "transparent"
        border.width: dropArea.containsDrag ? Style.normalBorderWidth : 0
        border.color: Color.accent
      }

      ColumnLayout {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.xxs

        Repeater {
          model: col.widgets
          delegate: WidgetRow {
            required property var modelData
            Layout.fillWidth: true
            widget: modelData
            placed: true
          }
        }

        Text {
          visible: col.widgets.length === 0
          text: barView.tr("empty")
          color: Util.alpha(Color.popups.text, 0.35)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          Layout.topMargin: Style.spacing.xs
        }
      }

      // The whole column is the target. The insertion point comes from where
      // in the column the pointer is, so a drop lands where it looks like it
      // will rather than always at the end.
      DropArea {
        id: dropArea
        anchors.fill: parent

        onDropped: function (drop) {
          var id = barView.dragId
          if (id === "")
            return
          var rowH = Style.spacing.popupRowHeight + Style.spacing.xxs
          var idx = Math.max(0, Math.min(col.widgets.length, Math.round(drop.y / rowH)))
          if (barView.entryFor(id) && barView.entryFor(id).placed)
            barView.moveWidget(id, col.section, idx)
          else
            barView.putWidget(id, col.section, idx)
          barView.dragId = ""
        }
      }
    }
  }

  // One widget. Draggable, clickable, and the keyboard cursor lands on it.
  //
  // Two items, not one. The outer cell is what the ColumnLayout positions and
  // it is never moved. The inner chip is what gets dragged, and its x and y are
  // relative to that cell, so putting it back at 0,0 returns it to its own slot.
  //
  // Dragging the layout-managed item directly does not work: a layout sets its
  // children's x and y, so assigning those from a drag fights it, and resetting
  // them afterwards parks the row at the column's origin on top of the first
  // widget until something else makes the layout run again.
  component WidgetRow: Item {
    id: cell
    property var widget: null
    property bool placed: true
    readonly property bool hasCursor: cell.widget !== null && barView.selectedId === cell.widget.id

    implicitHeight: Style.spacing.popupRowHeight
    implicitWidth: Style.space(140)

    Rectangle {
      id: chip
      width: cell.width
      height: cell.height
      radius: Style.cornerRadius
      color: cell.hasCursor ? Color.menu.selectedBackground
        : rowMouse.containsMouse ? Style.hoverFill : Util.alpha(Color.foreground, 0.04)
      border.width: cell.hasCursor ? Style.selectedBorderWidth : 0
      border.color: Color.accent

      // Lifted while dragging so it passes over the other columns rather than
      // under them.
      z: Drag.active ? 10 : 0
      opacity: Drag.active ? 0.7 : 1

      Drag.active: rowMouse.drag.active
      Drag.hotSpot.x: width / 2
      Drag.hotSpot.y: height / 2

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.sm
        anchors.rightMargin: Style.spacing.sm
        spacing: Style.spacing.xs

        Text {
          Layout.fillWidth: true
          text: cell.widget ? cell.widget.name : ""
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: cell.widget && cell.widget.missing ? Color.urgent
            : cell.hasCursor ? Color.menu.selectedText : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // A widget whose plugin is gone still occupies a slot; say so rather
        // than drawing a blank row.
        Text {
          visible: cell.widget !== null && cell.widget.missing === true
          text: barView.tr("missing")
          textFormat: Text.PlainText
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: cell.placed ? Qt.SizeAllCursor : Qt.PointingHandCursor
        drag.target: barView.busy ? null : chip
        drag.threshold: 6

        // Recorded on press rather than when the drag starts: MouseArea has no
        // onDragActiveChanged, drag.active lives in the drag group, and a drop
        // area only reads this at the moment of the drop anyway.
        onPressed: {
          if (!cell.widget)
            return
          barView.selectedId = cell.widget.id
          barView.dragId = cell.widget.id
          barView.dragPlaced = cell.placed
        }

        onReleased: {
          // Only after a real drag. Assigning x and y on a plain click would
          // move the chip for no reason.
          if (chip.Drag.active) {
            chip.Drag.drop()
            chip.x = 0
            chip.y = 0
          }
          barView.dragId = ""
        }
      }
    }
  }
}
