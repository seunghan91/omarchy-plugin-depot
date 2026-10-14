import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "I18n.js" as I18n

// One row in the plugin list.
//
// Deliberately anchor-based rather than built from RowLayout/ColumnLayout.
// This is a recycled delegate (`reuseItems`) in a list whose model is
// reassigned several times per open, as the catalog, the local inventory and
// the update check each land. With nested layouts, swapping `record` on a live
// delegate changes its children's implicit sizes in the middle of a rearrange,
// and Qt gives up with "Detected recursive rearrange. Aborting after two
// iterations." -- repeatedly, into the shell log.
//
// Anchors do not participate in that negotiation: the row's height is fixed and
// every child's width is resolved from the row's edges inward, so a record swap
// can never feed back into geometry.
Rectangle {
  id: row

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  property var record: null
  property bool selected: false

  // A local file:// path supplied by the panel, never a remote URL. Empty until
  // bin/pm-preview has fetched and validated the image.
  property string previewFile: ""

  signal clicked()

  implicitHeight: Style.space(58)
  radius: Style.cornerRadius
  color: row.selected ? Color.menu.selectedBackground
    : mouse.containsMouse ? Style.hoverFill : "transparent"

  readonly property int pad: Style.spacing.rowPaddingX
  readonly property int gap: Style.spacing.controlGap

  // ── preview ────────────────────────────────────────────────────────────
  // The initials tile is not a placeholder that gets swapped out: it stays
  // painted underneath, and the image simply covers it once decoded. A missing
  // or slow preview degrades to something legible instead of a hole.
  Item {
    id: tile
    anchors.left: parent.left
    anchors.leftMargin: row.pad
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(72)
    height: Style.space(42)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.foreground, 0.06)

      Text {
        anchors.centerIn: parent
        text: row.record ? row.record.initials : ""
        textFormat: Text.PlainText
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Image {
      anchors.fill: parent
      source: row.previewFile
      // Still asynchronous: this is a local file now, but decoding it on the
      // shell's UI thread would stutter the list while scrolling.
      asynchronous: true
      // cache is left at its default true. With delegate recycling, cache:false
      // would re-decode the same thumbnail every time the row scrolls back
      // into view instead of coming back from the pixmap cache.
      fillMode: Image.PreserveAspectCrop
      // Caps the decode. The fetcher already refuses oversized dimensions, so
      // this is the second of two bounds rather than the only one.
      sourceSize.width: Style.space(144)
      retainWhileLoading: true
      visible: status === Image.Ready
      smooth: true
    }
  }

  // ── rating, pinned right ───────────────────────────────────────────────
  Row {
    id: rating
    anchors.right: parent.right
    anchors.rightMargin: row.pad
    anchors.top: parent.top
    anchors.topMargin: Style.spacing.md
    spacing: row.gap

    Text {
      visible: row.record !== null && row.record.verified
      text: row.tr("verified")
      textFormat: Text.PlainText
      color: Util.alpha(Color.foreground, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: row.record !== null && row.record.hearts > 0
      text: row.record ? "♥ " + Model.formatCount(row.record.hearts) : ""
      textFormat: Text.PlainText
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: row.record !== null && row.record.stars > 0
      text: row.record ? "★ " + Model.formatCount(row.record.stars) : ""
      textFormat: Text.PlainText
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // ── state badges, to the left of the rating ────────────────────────────
  Row {
    id: badges
    anchors.right: rating.left
    anchors.rightMargin: rating.width > 0 ? row.gap : 0
    anchors.verticalCenter: name.verticalCenter
    spacing: Style.spacing.sm

    Badge {
      visible: row.record !== null && row.record.updateAvailable
      label: row.tr("update")
      tone: Color.urgent
    }

    Badge {
      visible: row.record !== null && row.record.installed && !row.record.updateAvailable
        && !row.record.firstParty
      label: row.record && row.record.enabled ? row.tr("installed") : row.tr("disabled")
      tone: row.record && row.record.enabled ? Color.accent : Color.muted
    }

    Badge {
      visible: row.record !== null && row.record.firstParty
      label: row.tr("built-in")
      tone: Color.muted
    }
  }

  // ── name and description ───────────────────────────────────────────────
  Text {
    id: name
    anchors.left: tile.right
    anchors.leftMargin: row.gap
    anchors.right: badges.left
    anchors.rightMargin: badges.width > 0 ? row.gap : 0
    anchors.top: parent.top
    anchors.topMargin: Style.spacing.md
    text: row.record ? row.record.name : ""
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: row.selected ? Color.menu.selectedText : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    anchors.left: tile.right
    anchors.leftMargin: row.gap
    anchors.right: parent.right
    anchors.rightMargin: row.pad
    anchors.top: name.bottom
    anchors.topMargin: Style.spacing.xxs
    text: {
      if (!row.record)
        return ""
      var bits = []
      if (row.record.author !== "")
        bits.push(row.record.author)
      if (row.record.kindLabel !== "")
        bits.push(Model.kindLabelText(row.record.kindLabel, row.lang))
      var lead = bits.join("  ·  ")
      var description = Model.descriptionText(row.record, row.lang)
      return lead === "" ? description : lead + "  —  " + description
    }
    textFormat: Text.PlainText
    elide: Text.ElideRight
    maximumLineCount: 1
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }

  component Badge: Rectangle {
    id: badge
    property string label: ""
    property color tone: Color.muted

    width: visible ? badgeText.implicitWidth + Style.spacing.controlGap : 0
    height: badgeText.implicitHeight + Style.spacing.xxs * 2
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 0
    color: Util.alpha(badge.tone, 0.16)

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: badge.label
      textFormat: Text.PlainText
      color: badge.tone
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
