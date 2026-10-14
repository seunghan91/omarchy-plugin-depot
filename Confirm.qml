import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Ui
import qs.Commons
import "I18n.js" as I18n

// The confirmation step in front of anything that changes the system.
//
// A plugin is arbitrary QML running unsandboxed inside the long-lived
// omarchy-shell process, so this dialog exists to show what is actually about
// to happen -- the exact repository, whether the marketplace has reviewed it,
// and for an update, the real commits and files that are about to land. That
// last part is why bin/pm-act has a read-only `diff` verb: reviewing a change
// should not require applying it first.
Item {
  id: confirm

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  // { verb: "install"|"update"|"remove"|"enable"|"disable", record: {...} }
  property var action: null
  property string binDir: ""

  signal confirmed()
  signal cancelled()

  readonly property var record: action ? action.record : null
  readonly property string verb: action ? String(action.verb) : ""
  readonly property bool destructive: verb === "remove"

  // ── the pin ────────────────────────────────────────────────────────────
  // The catalogue says which commit was reviewed; bin/pm-probe observes what
  // the repository points at right now. Two independent sources, so the feed
  // cannot quietly claim a repository has not moved.
  readonly property bool pinning: verb === "install" || verb === "update"
  readonly property string reviewedSha: record && record.reviewedCommit ? String(record.reviewedCommit) : ""
  property var probe: null
  property bool probing: false
  property bool acceptHead: false

  readonly property string headSha: probe && probe.head ? String(probe.head) : ""
  readonly property bool moved: probe !== null && probe.ok === true && probe.moved === true
  readonly property string probeError: probe && probe.ok === false ? String(probe.error || "") : ""

  // What will actually be installed. Defaults to the reviewed commit; only an
  // explicit opt-in switches it to the unreviewed head.
  readonly property string chosenSha: {
    if (!pinning)
      return ""
    if (acceptHead && headSha !== "")
      return headSha
    return reviewedSha
  }

  readonly property bool canProceed: {
    if (!pinning)
      return true
    if (probing)
      return false
    return chosenSha !== ""
  }

  onActionChanged: {
    diffText = ""
    probe = null
    acceptHead = false
    if (!action || binDir === "")
      return
    if (pinning && record && record.repo) {
      probing = true
      probeProc.running = true
    }
    if (verb === "update" && record) {
      diffText = I18n.later("Fetching the incoming changes...")
      diffProc.running = true
    }
  }

  property string diffText: ""

  // Scrim. Also swallows every click that misses the card, so the dialog is
  // genuinely modal rather than merely on top.
  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: confirm.cancelled()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(Style.space(560), parent.width - Style.space(48))
    height: Math.min(cardBody.implicitHeight + Style.spacing.huge * 2,
                     parent.height - Style.space(48))
    radius: Style.cornerRadius
    color: Color.menu.background
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(confirm.destructive ? Color.urgent : Color.menu.border,
                             Style.selectedBorderAlpha)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {}
    }

    ColumnLayout {
      id: cardBody
      anchors.fill: parent
      anchors.margins: Style.spacing.huge
      spacing: Style.spacing.md

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: confirm.destructive ? Color.urgent : Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        text: {
          if (!confirm.record)
            return ""
          var name = confirm.record.name
          switch (confirm.verb) {
          case "install": return confirm.tr("Install %1?", name)
          case "update": return confirm.tr("Update %1?", name)
          case "remove": return confirm.tr("Remove %1?", name)
          case "enable": return confirm.tr("Enable %1?", name)
          case "disable": return confirm.tr("Disable %1?", name)
          default: return name
          }
        }
      }

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        text: {
          switch (confirm.verb) {
          case "install":
            return confirm.tr("Omarchy will clone this repository into "
              + "~/.config/omarchy/plugins, validate its manifest, and enable it.")
          case "update":
            return confirm.tr("The checkout will be fast-forwarded to its origin and "
              + "re-validated. If validation fails the update is rolled back.")
          case "remove":
            return confirm.tr("The plugin's directory is deleted and it is taken out of "
              + "your shell layout. This cannot be undone from here.")
          case "enable":
            return confirm.tr("The shell will load this plugin.")
          case "disable":
            return confirm.tr("The plugin stays installed but the shell stops loading it.")
          default:
            return ""
          }
        }
      }

      // The repository is the thing actually being trusted, so it gets its own
      // line rather than being buried in the prose above.
      Rectangle {
        Layout.fillWidth: true
        visible: confirm.verb === "install" && confirm.record && confirm.record.repo !== ""
        implicitHeight: repoText.implicitHeight + Style.spacing.lg
        radius: Style.cornerRadius
        color: Util.alpha(Color.foreground, 0.06)

        Text {
          id: repoText
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          text: confirm.record ? confirm.record.repo : ""
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // What commit is about to be installed, and whether it is the one the
      // marketplace actually looked at.
      Rectangle {
        Layout.fillWidth: true
        visible: confirm.pinning
        implicitHeight: pinCol.implicitHeight + Style.spacing.lg
        radius: Style.cornerRadius
        color: Util.alpha(confirm.moved ? Color.urgent : Color.foreground, 0.08)

        ColumnLayout {
          id: pinCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.spacing.sm
          spacing: Style.spacing.xs

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: confirm.moved ? Color.urgent : Color.menu.text
            text: {
              if (confirm.probing)
                return confirm.tr("Checking what the repository points at now...")
              if (confirm.probeError !== "")
                return confirm.tr("Could not reach the repository: %1", confirm.probeError)
              if (confirm.reviewedSha === "")
                return confirm.tr("The marketplace has no reviewed commit for this listing, so "
                  + "there is nothing to pin to. Installing is not offered.")
              if (!confirm.moved)
                return confirm.tr("The repository is still at the commit the marketplace reviewed. "
                  + "Only that commit will be fetched.")
              return confirm.tr("This repository has moved since the marketplace reviewed it. "
                + "The newer code has not been reviewed.")
            }
          }

          Text {
            Layout.fillWidth: true
            visible: confirm.reviewedSha !== ""
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Util.alpha(Color.menu.text, 0.7)
            text: {
              var out = confirm.tr("reviewed  %1", confirm.reviewedSha.substring(0, 12))
              if (confirm.headSha !== "" && confirm.moved)
                out += "\n" + confirm.tr("now       %1", confirm.headSha.substring(0, 12))
              return out
            }
          }

          // Only offered once the repository is known to have moved. The
          // reviewed commit stays the default; taking the head is a deliberate
          // act, not a slip.
          ButtonGroup {
            visible: confirm.moved && confirm.reviewedSha !== ""
            options: [
              { value: "reviewed", label: confirm.tr("Install reviewed") },
              { value: "head", label: confirm.tr("Install newest (unreviewed)") }
            ]
            value: confirm.acceptHead ? "head" : "reviewed"
            fontSize: Style.font.caption
            onChanged: function (v) { confirm.acceptHead = (v === "head") }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: confirm.verb === "install"
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: confirm.record && confirm.record.verified ? Color.muted : Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        text: confirm.record && confirm.record.verified
          ? confirm.tr("The marketplace lists this as verified: its source has been reviewed. "
            + "A plugin still runs unsandboxed inside your shell process.")
          : confirm.tr("This listing is unverified. A plugin runs as arbitrary, unsandboxed "
            + "code inside your long-lived shell process — read its source before "
            + "you enable it.")
      }

      // The incoming diff for an update, straight from git.
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Style.space(90)
        visible: confirm.verb === "update"
        radius: Style.cornerRadius
        color: Util.alpha(Color.foreground, 0.06)

        Flickable {
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          clip: true
          contentWidth: width
          contentHeight: diffLabel.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: diffLabel
            width: parent.width
            text: confirm.tr(confirm.diffText)
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Util.alpha(Color.menu.text, 0.85)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.xs
        spacing: Style.spacing.md

        Text {
          text: confirm.canProceed ? confirm.tr("enter confirm    esc cancel") : confirm.tr("esc cancel")
          textFormat: Text.PlainText
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Item { Layout.fillWidth: true }

        Button {
          text: confirm.tr("Cancel")
          onClicked: confirm.cancelled()
        }

        Button {
          bordered: true
          enabled: confirm.canProceed
          foreground: confirm.destructive ? Color.urgent : Color.foreground
          text: {
            switch (confirm.verb) {
            case "install": return confirm.tr("Install")
            case "update": return confirm.tr("Update")
            case "remove": return confirm.tr("Remove")
            case "enable": return confirm.tr("Enable")
            case "disable": return confirm.tr("Disable")
            default: return confirm.tr("Confirm")
            }
          }
          onClicked: confirm.confirmed()
        }
      }
    }
  }

  // While this is up the panel's key catcher is deliberately blocked, so
  // without these two the keyboard dead-ends in front of every verb that
  // changes the system: you could open the dialog with the keyboard but not
  // finish or leave it. Enter is bound only while the action is actually
  // allowed, so it cannot fire past a failed probe.
  Shortcut {
    sequences: ["Return", "Enter"]
    enabled: confirm.visible && confirm.canProceed
    onActivated: confirm.confirmed()
  }

  Shortcut {
    sequences: ["Escape"]
    enabled: confirm.visible
    onActivated: confirm.cancelled()
  }

  Process {
    id: probeProc
    command: confirm.binDir === "" || !confirm.record || !confirm.record.repo
      ? [] : [confirm.binDir + "/pm-probe", confirm.record.repo, confirm.reviewedSha]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        confirm.probing = false
        try {
          confirm.probe = JSON.parse(text || "null")
        } catch (e) {
          confirm.probe = null
        }
      }
    }
    onExited: confirm.probing = false
  }

  Process {
    id: diffProc
    command: confirm.binDir === "" || !confirm.record
      ? [] : [confirm.binDir + "/pm-act", "diff", confirm.record.id, confirm.reviewedSha]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").replace(/__PM_DONE__ \d+\s*$/, "").trim()
        confirm.diffText = out === "" ? I18n.later("No changes reported.") : I18n.raw(out)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "")
          confirm.diffText = I18n.raw(msg)
      }
    }
  }
}
