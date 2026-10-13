import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Successor to the waybar custom/gpu-temp module. `sysmon-gpu` reports
// {"available":false} on a machine with no NVIDIA GPU, which hides the widget
// entirely -- the same behaviour as the old script printing an empty line.
BarWidget {
  id: root
  moduleName: "lunav0.gpu"

  property int percent: 0
  property int temp: -1
  property int vramUsed: 0
  property int vramTotal: 0
  property bool ready: false

  readonly property string label:
    "GPU " + percent + "%"
      + (temp >= 0 ? "  " + temp + "°" : "")
      + (vramTotal > 0 ? "  " + vramUsed + "/" + vramTotal + "G" : "")

  function refresh() {
    if (!proc.running) proc.running = true
  }

  visible: ready
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: ["sysmon-gpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let data
        try {
          data = JSON.parse(text || "{}")
        } catch (e) {
          return
        }
        if (data.available !== true) {
          root.ready = false
          return
        }

        root.percent = data.percent || 0
        root.temp = (typeof data.temp === "number") ? data.temp : -1
        root.vramUsed = data.vram_used || 0
        root.vramTotal = data.vram_total || 0
        root.ready = true
      }
    }
  }

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
    tooltipText: "VRAM " + root.vramUsed + "/" + root.vramTotal + " GB used"
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-launch-tui nvtop")
    }
  }
}
