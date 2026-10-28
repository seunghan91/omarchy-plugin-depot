import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons
import "I18n.js" as I18n
import "Model.js" as Model

// The running-action strip along the bottom.
//
// Both `job` and `log` are read from files written by bin/pm-job rather than
// held in memory, because the panel is destroyed part-way through every action
// it starts. That is also why this strip can appear already finished: if the
// panel was killed and re-summoned, the first thing it shows is the completed
// result of the job it never saw run.
Rectangle {
  id: strip

  // Display language, passed down from Panel.
  property string lang: "en"
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  property var job: null
  property string log: ""

  signal dismiss()

  readonly property string state: job ? String(job.state) : ""
  readonly property bool running: state === "running"
  readonly property bool failed: state === "failed"

  implicitHeight: body.implicitHeight + Style.spacing.lg * 2
  radius: Style.cornerRadius
  color: Util.alpha(strip.failed ? Color.urgent : Color.foreground, 0.07)

  ColumnLayout {
    id: body
    anchors.fill: parent
    anchors.margins: Style.spacing.lg
    spacing: Style.spacing.sm

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.controlGap

      Text {
        text: {
          if (!strip.job)
            return ""
          var phase = strip.running ? "running" : strip.failed ? "failed" : "finished"
          return strip.tr(Model.jobStatusKey(strip.job.verb, phase), strip.job.exit)
        }
        textFormat: Text.PlainText
        color: strip.failed ? Color.urgent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall

        // A quiet pulse rather than a spinner: there is no progress to report,
        // only that something is still happening.
        SequentialAnimation on opacity {
          running: strip.running
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutCubic }
          NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutCubic }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: strip.running
        text: strip.tr("The panel may close and reopen while this runs — that is the shell "
          + "reloading its plugins.")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item { Layout.fillWidth: true; visible: !strip.running }

      Button {
        visible: !strip.running
        text: strip.tr("Dismiss")
        fontSize: Style.font.caption
        onClicked: strip.dismiss()
      }
    }

    // Command output, tailed. Capped because a failed clone can print a great
    // deal and this strip is a status line, not a terminal.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(92)
      visible: strip.log !== ""
      radius: Style.cornerRadius
      color: Util.alpha(Color.background, 0.5)

      Flickable {
        id: logView
        anchors.fill: parent
        anchors.margins: Style.spacing.sm
        clip: true
        contentWidth: width
        contentHeight: logText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        // Keep the newest output in view without fighting a user who has
        // scrolled up to read something.
        onContentHeightChanged: {
          if (!logView.moving && strip.running)
            logView.contentY = Math.max(0, contentHeight - height)
        }

        Text {
          id: logText
          width: parent.width
          text: {
            var lines = strip.log.replace(/__PM_DONE__ \d+\s*$/, "").split("\n")
            if (lines.length > 200)
              lines = lines.slice(lines.length - 200)
            return lines.join("\n").trim()
          }
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
          color: Util.alpha(Color.foreground, 0.8)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
