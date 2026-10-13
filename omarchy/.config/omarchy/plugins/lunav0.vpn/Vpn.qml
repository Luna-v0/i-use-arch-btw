import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// VPN state straight from NetworkManager. Reads `nmcli connection show
// --active` and reports any vpn/wireguard connection that is up.
//
// tun devices are deliberately NOT counted: tailscale registers as `tun` and
// already has its own bar widget, so counting it would leave this pill
// permanently lit and say nothing about the work VPN.
BarWidget {
  id: root
  moduleName: "lunav0.vpn"

  // Which profile the click connects when nothing is up. Set it per-bar with:
  //   omarchy bar set lunav0.vpn connection "tecgraf_vpn"
  // Falls back to the first configured vpn profile NetworkManager reports.
  readonly property string preferred:
    (settings && settings.connection) ? String(settings.connection) : root.firstProfile

  property string firstProfile: ""
  property string activeName: ""
  readonly property bool connected: activeName !== ""

  // nmcli -t escapes literal colons in names as "\:". Split without a regex
  // lookbehind: QML's JS engine does not reliably support those, and a silently
  // failing parse here is indistinguishable from "VPN is down".
  function splitFields(line) {
    var SENTINEL = "\u0000"
    var parts = line.split("\\:").join(SENTINEL).split(":")
    for (var i = 0; i < parts.length; i++) {
      parts[i] = parts[i].split(SENTINEL).join(":")
    }
    return parts
  }

  function refresh() {
    if (!activeProc.running) activeProc.running = true
  }

  function toggle() {
    if (!root.bar) return
    if (root.connected) {
      root.bar.run("nmcli connection down " + Util.shellQuote(root.activeName))
    } else if (root.preferred !== "") {
      root.bar.run("nmcli connection up " + Util.shellQuote(root.preferred))
    }
    // NetworkManager takes a moment to settle; re-read rather than guess.
    settleTimer.restart()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    profilesProc.running = true
    refresh()
  }

  // Active vpn/wireguard connections.
  Process {
    id: activeProc
    command: ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show", "--active"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i] === "") continue
          // -t escapes literal colons as \: , so unescape after splitting.
          var parts = root.splitFields(lines[i])
          if (parts.length < 3) continue
          var type = parts[parts.length - 2]
          var state = parts[parts.length - 1]
          if ((type === "vpn" || type === "wireguard") && state === "activated") {
            found = parts.slice(0, parts.length - 2).join(":")
            break
          }
        }
        root.activeName = found
      }
    }
  }

  // Configured vpn profiles, for the default click target.
  Process {
    id: profilesProc
    command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i] === "") continue
          var parts = root.splitFields(lines[i])
          if (parts.length < 2) continue
          if (parts[parts.length - 1] !== "vpn") continue
          var name = parts.slice(0, parts.length - 1).join(":")
          // Skip profiles that look retired, so the default click does not
          // bring up an old copy.
          if (/_old$/.test(name)) continue
          root.firstProfile = name
          break
        }
      }
    }
  }

  Timer {
    id: settleTimer
    interval: 1500
    repeat: false
    onTriggered: root.refresh()
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
    text: "VPN"
    fontSize: Style.font.caption
    horizontalMargin: 6
    // Same convention the workspaces widget uses for empty vs occupied.
    opacity: root.connected ? 1 : 0.5
    tooltipText: root.connected
      ? "VPN connected: " + root.activeName + "\nClick to disconnect"
      : (root.preferred !== ""
          ? "VPN disconnected\nClick to connect " + root.preferred + "\nRight-click for nmtui"
          : "VPN disconnected\nNo profile configured")
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-launch-tui nmtui")
      } else {
        root.toggle()
      }
    }
  }
}
