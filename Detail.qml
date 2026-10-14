import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "I18n.js" as I18n

// The right-hand pane: everything known about one plugin, and the actions
// available for it.
//
// Which actions exist is derived from the record rather than from a stored
// mode, so a plugin that is installed while this pane is open shows the right
// buttons the moment the inventory refreshes.
Item {
  id: detail

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  property var record: null
  property bool jobRunning: false

  // A local file:// path supplied by the panel, never a remote URL.
  property string previewFile: ""

  // Set when this pane has replaced the list on a narrow window, so it needs a
  // way back to it.
  property bool showBack: false

  // Emitted with an action verb that bin/pm-act understands.
  signal act(string verb)
  signal back()

  readonly property bool isInstalled: record !== null && record.installed
  readonly property bool isFirstParty: record !== null && record.firstParty
  readonly property bool canInstall: record !== null && !isInstalled && record.installable
  readonly property bool canUpdate: record !== null && isInstalled && record.updateAvailable
    && !record.gitDirty

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(Color.popups.border, Style.normalBorderAlpha)
  }

  Text {
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    visible: detail.record === null
    text: detail.tr("Select a plugin to see what it is and what you can do with it.")
    textFormat: Text.PlainText
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.spacing.popupPadding
    visible: detail.record !== null
    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: body
      width: parent.width
      spacing: Style.spacing.md

      Button {
        visible: detail.showBack
        text: "‹  " + detail.tr("All plugins")
        fontSize: Style.font.bodySmall
        leftAlign: true
        onClicked: detail.back()
      }

      // Screenshot. Sized to a 16:9 box and only shown once decoded, so the
      // layout does not jump when a slow preview lands.
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: shot.status === Image.Ready ? width * 0.5625 : 0
        visible: shot.status === Image.Ready

        Image {
          id: shot
          anchors.fill: parent
          source: detail.previewFile
          asynchronous: true
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Style.space(800)
          retainWhileLoading: true
          smooth: true
        }
      }

      Text {
        Layout.fillWidth: true
        text: detail.record ? detail.record.name : ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }

      Text {
        Layout.fillWidth: true
        text: {
          if (!detail.record)
            return ""
          var bits = []
          if (detail.record.author !== "")
            bits.push(detail.tr("by %1", detail.record.author))
          if (detail.record.version !== "")
            bits.push("v" + detail.record.version)
          if (detail.record.kindLabel !== "")
            bits.push(Model.kindLabelText(detail.record.kindLabel, detail.lang))
          return bits.join("  ·  ")
        }
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // Marketplace engagement. Hearts, views and copies come from the
      // marketplace's own API rather than the catalog file, so they are absent
      // for anything it does not list -- in which case this row says nothing
      // instead of showing a misleading row of zeroes.
      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.lg
        // Only when there is a number worth showing -- a plugin with a stats
        // row of all zeroes would otherwise leave an empty band here.
        visible: detail.record !== null
          && (detail.record.hearts > 0 || detail.record.stars > 0
              || detail.record.views > 0 || detail.record.copies > 0)

        Stat {
          count: detail.record ? detail.record.hearts : 0
          glyph: "♥"
          noun: detail.tr("heart")
          plural: detail.tr("hearts")
        }

        Stat {
          count: detail.record ? detail.record.stars : 0
          glyph: "★"
          noun: detail.tr("star")
          plural: detail.tr("stars")
        }

        Stat {
          count: detail.record ? detail.record.views : 0
          noun: detail.tr("view")
          plural: detail.tr("views")
        }

        Stat {
          count: detail.record ? detail.record.copies : 0
          noun: detail.tr("install")
          plural: detail.tr("installs")
        }
      }

      Text {
        Layout.fillWidth: true
        text: Model.descriptionText(detail.record, detail.lang)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        lineHeight: 1.25
      }

      // ── state notices ────────────────────────────────────────────────

      Notice {
        Layout.fillWidth: true
        visible: detail.record !== null && detail.record.gitDirty
        tone: Color.urgent
        text: detail.tr("This plugin's files have been edited locally, so an update cannot "
          + "fast-forward. Revert the changes in %1 to update it.", detail.record ? detail.record.sourceDir : "")
      }

      Notice {
        Layout.fillWidth: true
        visible: detail.record !== null && detail.record.updateStatus === "unreachable"
        tone: Color.muted
        text: detail.tr("Could not reach this plugin's origin to check for updates.")
      }

      Notice {
        Layout.fillWidth: true
        visible: detail.record !== null && !detail.record.installed
          && !detail.record.installable && detail.record.installNote !== ""
        tone: Color.muted
        text: Model.installNoteText(detail.record, detail.lang)
      }

      Notice {
        Layout.fillWidth: true
        visible: detail.record !== null && detail.record.installed
          && !detail.record.listed && !detail.record.firstParty
        tone: Color.muted
        text: detail.tr("Installed on this machine but not listed in the marketplace.")
      }

      // ── actions ──────────────────────────────────────────────────────

      Flow {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.xs
        spacing: Style.spacing.md

        Button {
          visible: detail.canInstall
          text: detail.tr("Install")
          bordered: true
          enabled: !detail.jobRunning
          tooltipText: detail.tr("Clone and enable this plugin")
          onClicked: detail.act("install")
        }

        Button {
          visible: detail.canUpdate
          text: detail.tr("Update")
          bordered: true
          enabled: !detail.jobRunning
          tooltipText: detail.tr("Review the incoming changes, then fast-forward this plugin")
          onClicked: detail.act("update")
        }

        Button {
          visible: detail.isInstalled && !detail.isFirstParty && detail.record.canDisable
          text: detail.record && detail.record.enabled ? detail.tr("Disable") : detail.tr("Enable")
          enabled: !detail.jobRunning
          tooltipText: detail.record && detail.record.enabled
            ? detail.tr("Keep it installed but stop loading it")
            : detail.tr("Load this plugin in the shell")
          onClicked: detail.act(detail.record.enabled ? "disable" : "enable")
        }

        Button {
          visible: detail.isInstalled && !detail.isFirstParty
          text: detail.tr("Remove")
          enabled: !detail.jobRunning
          foreground: Color.urgent
          tooltipText: detail.tr("Delete this plugin from ~/.config/omarchy/plugins")
          onClicked: detail.act("remove")
        }

        Button {
          visible: detail.record !== null && detail.record.repo !== ""
          text: detail.tr("Repository")
          fontSize: Style.font.bodySmall
          tooltipText: detail.record ? detail.record.repo : ""
          onClicked: Quickshell.execDetached(["xdg-open", detail.record.repo])
        }

        Button {
          visible: detail.record !== null && detail.record.marketplaceUrl !== ""
          text: detail.tr("Plugin page")
          fontSize: Style.font.bodySmall
          tooltipText: detail.record ? detail.record.marketplaceUrl : ""
          onClicked: Quickshell.execDetached(["xdg-open", detail.record.marketplaceUrl])
        }
      }

      PanelSeparator {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.sm
        Layout.bottomMargin: Style.spacing.sm
      }

      // ── facts ────────────────────────────────────────────────────────

      SectionLabel {
        Layout.fillWidth: true
        text: detail.tr("LISTING")
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Plugin id")
        value: detail.record ? detail.record.id : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Category")
        value: detail.record ? detail.tr(detail.record.category) : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Tags")
        value: detail.record && detail.record.tags.length ? detail.record.tags.join(", ") : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Licence")
        value: detail.record ? detail.record.license : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Listing")
        value: {
          if (!detail.record || !detail.record.listed)
            return ""
          return detail.record.verified ? detail.tr("Verified by the marketplace") : detail.tr("Unverified listing")
        }
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Repo updated")
        value: detail.record && detail.record.repoUpdatedAt
          ? Model.relativeDate(detail.record.repoUpdatedAt, clock.now, detail.lang) : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Update")
        value: detail.record && detail.record.updateAvailable
          ? detail.record.updateFrom + " → " + detail.record.updateTo : ""
      }

      // ── metadata ─────────────────────────────────────────────────────
      // What is actually on disk, from the plugin's own manifest and its git
      // checkout. Only meaningful once installed, so the whole block hides
      // until then rather than showing a column of blanks.

      SectionLabel {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.sm
        visible: detail.isInstalled
        text: detail.tr("METADATA")
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Kinds")
        // Gated on being installed like the rest of this block: a listing
        // carries a kind too, and showing it here would leave one orphaned row
        // under a hidden METADATA heading.
        value: detail.isInstalled && detail.record.kinds.length
          ? detail.record.kinds.map(function (k) { return detail.tr(k) }).join(", ") : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Entry points")
        value: {
          if (!detail.record || !detail.record.entryPoints)
            return ""
          var out = []
          for (var kind in detail.record.entryPoints)
            out.push(detail.tr(kind) + ": " + detail.record.entryPoints[kind])
          return out.join("\n")
        }
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Enabled")
        value: detail.isInstalled ? (detail.record.enabled ? detail.tr("yes") : detail.tr("no")) : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Cloned from")
        value: detail.record ? detail.record.clonedFrom : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Settings")
        value: detail.record && detail.record.settingsSchema.length
          ? detail.trn(detail.record.settingsSchema.length,
                       "%1 option in shell.json", "%1 options in shell.json")
          : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Installed at")
        value: detail.record ? detail.record.sourceDir : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Reviewed at")
        value: detail.record && detail.record.reviewedCommit
          ? detail.record.reviewedCommit.substring(0, 12) : ""
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Pinned")
        // Whether what is on disk is the commit the marketplace reviewed. This
        // is the visible payoff of installing a pinned commit rather than a
        // moving branch head.
        value: {
          if (!detail.isInstalled || !detail.record.gitManaged)
            return ""
          var reviewed = detail.record.reviewedCommit || ""
          var head = detail.record.gitHead || ""
          if (reviewed === "" || head === "")
            return ""
          return head === reviewed
            ? detail.tr("yes — at the reviewed commit")
            : detail.tr("no — this checkout is not the reviewed commit")
        }
      }

      Fact {
        Layout.fillWidth: true
        label: detail.tr("Tracking")
        value: {
          if (!detail.record || !detail.record.gitManaged)
            return detail.isInstalled ? detail.tr("not a git checkout") : ""
          var bits = []
          if (detail.record.gitBranch !== "")
            bits.push(detail.record.gitBranch)
          if (detail.record.gitHead !== "")
            bits.push(detail.record.gitHead.substring(0, 7))
          bits.push(detail.record.gitDirty ? detail.tr("locally modified") : detail.tr("clean"))
          return bits.join("  ·  ")
        }
      }
    }
  }

  // Only advanced when the pane is actually showing something, so an idle
  // panel is not waking up once a minute to recompute "3d ago".
  Timer {
    id: clock
    property double now: Date.now()
    running: detail.visible && detail.record !== null
    interval: 60000
    repeat: true
    triggeredOnStart: true
    onTriggered: now = Date.now()
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // One engagement count: an optional glyph, the number, and what it counts.
  // Hides itself at zero, so the caller can list every stat unconditionally and
  // let each decide whether it has anything to say.
  component Stat: Row {
    id: stat
    property int count: 0
    property string glyph: ""
    property string noun: ""
    property string plural: noun + "s"

    visible: stat.count > 0
    spacing: Style.spacing.xs

    Text {
      visible: stat.glyph !== ""
      text: stat.glyph
      textFormat: Text.PlainText
      color: Util.alpha(Color.popups.text, 0.75)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      text: Model.formatCount(stat.count)
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      // "1 heart", but "1.2k hearts" — the compact form is never singular.
      text: stat.count === 1 ? stat.noun : stat.plural
      textFormat: Text.PlainText
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  component Fact: RowLayout {
    id: fact
    property string label: ""
    property string value: ""

    visible: fact.value !== ""
    spacing: Style.spacing.controlGap

    Text {
      Layout.preferredWidth: Style.space(96)
      Layout.alignment: Qt.AlignTop
      text: fact.label
      textFormat: Text.PlainText
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      Layout.fillWidth: true
      text: fact.value
      textFormat: Text.PlainText
      wrapMode: Text.WrapAnywhere
      color: Util.alpha(Color.popups.text, 0.85)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  component Notice: Rectangle {
    id: notice
    property string text: ""
    property color tone: Color.muted

    implicitHeight: noticeText.implicitHeight + Style.spacing.lg
    radius: Style.cornerRadius
    color: Util.alpha(notice.tone, 0.10)

    Text {
      id: noticeText
      anchors.fill: parent
      anchors.margins: Style.spacing.sm
      text: notice.text
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: notice.tone
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
