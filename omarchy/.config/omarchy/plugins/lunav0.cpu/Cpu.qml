import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Successor to the waybar custom/cpu-temp module. Data comes from `sysmon-cpu`,
// which reports CPU load as a delta against its own previous /proc/stat reading
// instead of blocking on `mpstat 1 1` the way the old shell script did.
BarWidget {
  id: root
  moduleName: "lunav0.cpu"

  property int percent: 0
  property int temp: -1
  property int ramUsed: 0
  property int ramTotal: 0
  property bool ready: false

  readonly property string label:
    "CPU " + percent + "%"
      + (temp >= 0 ? "  " + temp + "°" : "")
      + (ramTotal > 0 ? "  " + ramUsed + "/" + ramTotal + "G" : "")

  function refresh() {
    if (!proc.running) proc.running = true
  }

  visible: ready
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: ["sysmon-cpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let data
        try {
          data = JSON.parse(text || "{}")
        } catch (e) {
          return
        }
        if (typeof data.percent !== "number") return

        root.percent = data.percent
        root.temp = (typeof data.temp === "number") ? data.temp : -1
        root.ramUsed = data.ram_used || 0
        root.ramTotal = data.ram_total || 0
        root.ready = true
      }
    }
  }

  // The first reading can only report 0%, because the delta it would be
  // measured against does not exist yet. Poll on start anyway so that snapshot
  // gets written, and the reading 5s later is the first real one.
  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: "RAM " + root.ramUsed + "/" + root.ramTotal + " GB used"
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-launch-tui btop")
    }
  }
}
