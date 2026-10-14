import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget: opens the plugin manager, and says when plugin updates are
// waiting.
//
// A bar widget gets `bar`, `moduleName` and `settings` injected -- not `shell`
// and not `manifest` -- so the shell is reached through `bar.shell` and this
// plugin's own directory through the registry. `bar` is null during
// Component.onCompleted, which is why the first update check is triggered from
// onBarChanged rather than at construction.
BarWidget {
  id: root

  readonly property string pluginId: "io.github.seunghan91.plugin-depot-ko"

  readonly property var pluginManifest: {
    if (!bar || !bar.shell || !bar.shell.pluginRegistry)
      return null
    var installed = bar.shell.pluginRegistry.installedPlugins
    return installed ? installed[root.pluginId] : null
  }

  // Two ways this comes back empty on newer Omarchy: a third-party widget gets
  // a PluginShellApi as `bar.shell`, which has no pluginRegistry at all, so
  // pluginManifest is null, and even when the manifest is reachable its
  // __sourceDir has been stripped. Either way the update check never ran and
  // the badge could never appear. The widget's own file URL is not subject to
  // either, so it is the fallback.
  readonly property string binDir: (pluginManifest && pluginManifest.__sourceDir
    ? String(pluginManifest.__sourceDir)
    : decodeURIComponent(String(Qt.resolvedUrl("."))
      .replace(/^file:\/\//, "")).replace(/\/$/, "")) + "/bin"

  property int updateCount: 0
  property bool checked: false

  // "always" | "updates" | "never", set from the panel's Settings view via
  // `omarchy bar set io.github.seunghan91.plugin-depot-ko showInBar <value>`.
  //
  // "never" hides the widget rather than removing it from the bar layout. That
  // entry is also what marks the plugin enabled, and a plugin the shell thinks
  // is disabled cannot be summoned at all -- taking it out of the layout would
  // hide the icon by making the whole app unreachable. An invisible widget
  // collapses its slot to 0x0, so it costs nothing but keeps the app openable.
  readonly property string showInBar: {
    var v = String(root.setting("showInBar", "always"))
    return (v === "always" || v === "updates" || v === "never") ? v : "always"
  }

  // 0 means never poll; anything else is floored so a typo cannot put the
  // widget into a tight network loop.
  readonly property int checkMinutes: {
    var m = Number(root.setting("updateCheckMinutes", 180))
    if (!isFinite(m) || m <= 0)
      return 0
    return Math.max(15, Math.round(m))
  }

  visible: root.showInBar === "always"
    || (root.showInBar === "updates" && root.updateCount > 0)

  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  onBarChanged: if (bar) Qt.callLater(root.checkNow)

  function checkNow() {
    if (root.binDir === "" || updatesProc.running)
      return
    updatesProc.running = true
  }

  function openManager() {
    if (bar && bar.shell && typeof bar.shell.toggle === "function")
      bar.shell.toggle(root.pluginId, "")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-puzzle — the same glyph the Omarchy menu uses for its Plugins
    // section, so the bar and the menu agree on what this is.
    text: "\udb81\udc31"
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton)
        root.checkNow()
      else
        root.openManager()
    }

    // Update count, tucked into the corner of the glyph.
    Rectangle {
      visible: root.updateCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(2)
      anchors.topMargin: Style.space(3)
      width: countText.implicitWidth + Style.space(4)
      height: countText.implicitHeight + Style.space(1)
      radius: height / 2
      color: Color.bar.active

      Text {
        id: countText
        anchors.centerIn: parent
        text: root.updateCount > 9 ? "9+" : String(root.updateCount)
        textFormat: Text.PlainText
        color: Color.bar.background
        font.family: Style.font.family
        font.pixelSize: Math.max(8, Math.round(Style.font.caption * 0.8))
      }
    }
  }

  Process {
    id: updatesProc
    command: root.binDir === "" ? [] : [root.binDir + "/pm-updates"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "null")
          root.updateCount = parsed && parsed.available ? Number(parsed.available) : 0
          root.checked = true
        } catch (e) {
          root.updateCount = 0
        }
      }
    }
  }

  Timer {
    running: root.binDir !== "" && root.checkMinutes > 0
    interval: root.checkMinutes * 60000
    repeat: true
    onTriggered: root.checkNow()
  }

  // The manager acts on the same plugins this counts, so re-check whenever the
  // registry changes rather than waiting out the interval.
  Connections {
    target: root.bar && root.bar.shell ? root.bar.shell.pluginRegistry : null
    ignoreUnknownSignals: true
    function onPluginsChanged() {
      Qt.callLater(root.checkNow)
    }
  }
}
