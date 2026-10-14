import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons
import "I18n.js" as I18n

// The scope and category switcher.
//
// Used two ways with the same content: as an inline column when the window is
// wide enough to spare 180px, and as an overlay drawer when it is not. A window
// tiled at 621px — which is what Hyprland hands this panel by default — has no
// room for a permanent column without squeezing the list to nothing, but it
// must not lose the categories either. A drawer costs width only while it is
// open.
Item {
  id: sidebar

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  property var scopes: []
  property var categories: []
  property string scope: ""
  property string category: ""

  signal scopeChosen(string key)
  signal categoryChosen(string name)

  implicitWidth: Style.space(180)

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.xs

    Repeater {
      model: sidebar.scopes
      delegate: ScopeRow {
        required property var modelData
        Layout.fillWidth: true
        label: modelData.label
        count: modelData.count
        highlight: modelData.key === "updates" && modelData.count > 0
        selected: sidebar.scope === modelData.key
        onClicked: sidebar.scopeChosen(modelData.key)
      }
    }

    PanelSeparator {
      Layout.fillWidth: true
      Layout.topMargin: Style.spacing.sm
      Layout.bottomMargin: Style.spacing.sm
    }

    Text {
      visible: sidebar.categories.length > 0
      text: sidebar.tr("CATEGORIES")
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      Layout.bottomMargin: Style.spacing.xs
    }

    ListView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      reuseItems: true
      model: sidebar.categories
      spacing: 0
      delegate: ScopeRow {
        required property var modelData
        width: ListView.view.width
        // The catalogue's own category name; the selection still keys on it.
        label: sidebar.tr(modelData.name)
        count: modelData.count
        selected: sidebar.category === modelData.name
        onClicked: sidebar.categoryChosen(modelData.name)
      }
    }
  }

  // One row: a label, an optional count, and a hover/selected ground.
  component ScopeRow: Rectangle {
    id: scopeRow

    property string label: ""
    property int count: 0
    property bool selected: false
    property bool highlight: false

    signal clicked()

    implicitHeight: Style.spacing.popupRowHeight
    radius: Style.cornerRadius
    color: scopeRow.selected ? Color.menu.selectedBackground
      : mouse.containsMouse ? Style.hoverFill : "transparent"

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.controlGap
      spacing: Style.spacing.sm

      Text {
        Layout.fillWidth: true
        text: scopeRow.label
        elide: Text.ElideRight
        textFormat: Text.PlainText
        color: scopeRow.selected ? Color.menu.selectedText : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: scopeRow.count > 0
        text: String(scopeRow.count)
        textFormat: Text.PlainText
        color: scopeRow.highlight ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: scopeRow.clicked()
    }
  }
}
