import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Ui
import qs.Commons
import "I18n.js" as I18n

// Settings for the manager itself.
//
// Everything here is stored where Omarchy already stores it -- inline on this
// plugin's entry in shell.json's bar layout -- and is written through the
// `omarchy bar` commands rather than by editing that file. The shell owns
// shell.json and rewrites it whenever the bar changes; writing it from here
// would race its writer.
//
// Reading is the same story: pm-settings asks the running shell for its
// effective config instead of parsing the file behind its back.
Item {
  id: settings

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  property string binDir: ""
  property string pluginId: "io.github.omarcodehub.plugin-manager"

  // Last state read back from the shell.
  property var state: null
  property bool loading: false
  property string error: ""

  readonly property string showInBar: {
    if (!state || !state.settings)
      return "always"
    var v = String(state.settings.showInBar || "always")
    return (v === "always" || v === "updates" || v === "never") ? v : "always"
  }

  readonly property string section: state && state.section ? String(state.section) : "right"
  readonly property bool inBar: state !== null && state.inBar === true

  // "auto" | "en" | "ko", the stored choice rather than the resolved language:
  // "auto" has to stay selectable. Panel resolves it against the locale.
  readonly property string language: {
    if (!state || !state.settings)
      return "auto"
    var v = String(state.settings.language || "auto")
    return I18n.languages.indexOf(v) >= 0 ? v : "auto"
  }

  readonly property int checkMinutes: {
    if (!state || !state.settings || state.settings.updateCheckMinutes === undefined)
      return 180
    var m = Number(state.settings.updateCheckMinutes)
    return isFinite(m) && m >= 0 ? Math.round(m) : 180
  }

  function reload() {
    if (settings.binDir === "")
      return
    settings.loading = true
    readProc.running = true
  }

  function apply(verb, a, b) {
    if (settings.binDir === "" || applyProc.running)
      return
    settings.error = ""
    applyProc.pending = verb === "bar-move"
      ? ["bar-move", settings.pluginId, a]
      : ["bar-set", settings.pluginId, a, String(b)]
    applyProc.running = true
  }

  onVisibleChanged: if (visible) settings.reload()
  // Read once at load as well, not only when the view is shown: Panel takes its
  // display language from `language`, and needs it before Settings is opened.
  Component.onCompleted: settings.reload()
  onBinDirChanged: if (visible) settings.reload()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(Color.popups.border, Style.normalBorderAlpha)
  }

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: body
      width: parent.width
      spacing: Style.spacing.lg

      Text {
        text: settings.tr("Settings")
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }

      Text {
        Layout.fillWidth: true
        visible: settings.error !== ""
        text: settings.tr(settings.error)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // ── bar presence ────────────────────────────────────────────────

      Field {
        Layout.fillWidth: true
        label: settings.tr("Show in the bar")
        description: settings.showInBar === "never"
          ? settings.tr("The bar icon is hidden and takes up no space. Open the manager from "
            + "the Omarchy menu, a keybinding, or `omarchy-shell shell toggle %1`.",
            settings.pluginId)
          : settings.showInBar === "updates"
            ? settings.tr("The icon appears only while an installed plugin has an update waiting.")
            : settings.tr("The icon is always in the bar, with a count when updates are waiting.")

        ButtonGroup {
          options: [
            { value: "always", label: settings.tr("Always") },
            { value: "updates", label: settings.tr("When updates wait") },
            { value: "never", label: settings.tr("Never") }
          ]
          value: settings.showInBar
          fontSize: Style.font.bodySmall
          enabled: !settings.loading && !applyProc.running
          onChanged: function (v) { settings.apply("bar-set", "showInBar", v) }
        }
      }

      Field {
        Layout.fillWidth: true
        label: settings.tr("Position")
        description: settings.showInBar === "never"
          ? settings.tr("Which section the icon would sit in, if it were shown.")
          : settings.tr("Which section of the bar the icon sits in.")

        ButtonGroup {
          options: [
            { value: "left", label: settings.tr("Left") },
            { value: "center", label: settings.tr("Centre") },
            { value: "right", label: settings.tr("Right") }
          ]
          value: settings.section
          fontSize: Style.font.bodySmall
          enabled: settings.inBar && !settings.loading && !applyProc.running
          onChanged: function (v) { settings.apply("bar-move", v) }
        }
      }

      PanelSeparator {
        Layout.fillWidth: true
      }

      // ── update checking ─────────────────────────────────────────────

      Field {
        Layout.fillWidth: true
        label: settings.tr("Check for updates")
        description: settings.checkMinutes === 0
          ? settings.tr("The bar widget will not poll on its own. The manager still checks "
            + "every time you open it.")
          : settings.tr("How often the bar widget asks each installed plugin's origin whether "
            + "it has moved. One lightweight ref lookup per plugin; nothing is downloaded.")

        ButtonGroup {
          options: [
            { value: "60", label: settings.tr("Hourly") },
            { value: "180", label: settings.tr("3 hours") },
            { value: "720", label: settings.tr("12 hours") },
            { value: "0", label: settings.tr("Never") }
          ]
          value: String(settings.checkMinutes)
          fontSize: Style.font.bodySmall
          enabled: !settings.loading && !applyProc.running
          onChanged: function (v) { settings.apply("bar-set", "updateCheckMinutes", v) }
        }
      }

      PanelSeparator {
        Layout.fillWidth: true
      }

      // ── display language ────────────────────────────────────────────

      Field {
        Layout.fillWidth: true
        label: settings.tr("Language")
        description: settings.tr("Auto follows the system locale. Languages without a "
          + "translation fall back to English.")

        ButtonGroup {
          // Language names stay in their own language, so each is findable
          // whatever the current one is.
          options: I18n.languages.map(function (code) {
            return { value: code, label: code === "auto" ? settings.tr("Auto") : I18n.languageNames[code] }
          })
          value: settings.language
          fontSize: Style.font.bodySmall
          enabled: !settings.loading && !applyProc.running
          onChanged: function (v) { settings.apply("bar-set", "language", v) }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.topMargin: Style.spacing.sm
        text: settings.tr("Stored on this plugin's entry in ~/.config/omarchy/shell.json, "
          + "written through the omarchy bar commands.")
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Util.alpha(Color.popups.text, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Process {
    id: readProc
    command: settings.binDir === "" ? [] : [settings.binDir + "/pm-settings", "--id", settings.pluginId]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        settings.loading = false
        try {
          var parsed = JSON.parse(text || "null")
          if (parsed && parsed.ok) {
            settings.state = parsed
            settings.error = ""
          } else {
            settings.error = parsed && parsed.error
              ? I18n.raw(String(parsed.error)) : I18n.later("Could not read the current settings.")
          }
        } catch (e) {
          settings.error = I18n.later("Could not read the current settings.")
        }
      }
    }
    onExited: settings.loading = false
  }

  Process {
    id: applyProc
    property var pending: []
    command: settings.binDir === "" || pending.length === 0
      ? [] : [settings.binDir + "/pm-act"].concat(pending)
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "")
          settings.error = I18n.raw(msg)
      }
    }
    onExited: function (exitCode) {
      if (exitCode !== 0 && settings.error === "")
        settings.error = I18n.later("That change could not be applied (exit %1).", exitCode)
      // The shell rewrites shell.json asynchronously, so read back rather than
      // assuming the value we asked for is the value that landed.
      reloadDelay.restart()
    }
  }

  Timer {
    id: reloadDelay
    interval: 400
    onTriggered: settings.reload()
  }

  component Field: ColumnLayout {
    id: field
    property string label: ""
    property string description: ""
    default property alias content: holder.data

    spacing: Style.spacing.xs

    Text {
      text: field.label
      textFormat: Text.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    Text {
      Layout.fillWidth: true
      text: field.description
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Item {
      id: holder
      Layout.fillWidth: true
      Layout.topMargin: Style.spacing.xs
      implicitHeight: childrenRect.height
    }
  }
}
