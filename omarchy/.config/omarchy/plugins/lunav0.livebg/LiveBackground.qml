import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A drawn, animated layer that sits on the background layer just above the
// wallpaper. Nothing is pre-rendered and there is no video file -- these are
// GPU-drawn radial gradients whose positions are animated, so it costs a few
// shapes per frame rather than decoding anything.
//
// Colours come from the live theme, so a `dynamic-theme` run re-colours the
// aurora at the same moment it re-colours the borders and the bar.
Scope {
  id: root

  // The wallpaper-derived six-stop gradient that also drives the Hyprland
  // active border. Falls back to the foundational palette on a theme that
  // does not ship one.
  readonly property var paletteColors: {
    const raw = Color.shellValues["hyprland.active-border"] || ""
    const tokens = String(raw).trim().split(/\s+/).filter(t => t && !t.match(/^-?\d+(?:\.\d+)?deg$/))
    return tokens.length >= 3 ? tokens : [Color.accent, Color.foreground, Color.muted]
  }

  // How strongly the aurora reads over the wallpaper. This is the knob to turn:
  // windows here are 90%/80% opaque, so whatever is on the background layer
  // tints app content too. 0.10-0.14 stays a mood; past ~0.2 it starts washing
  // over what you are reading. Saving this file re-applies it immediately.
  readonly property real intensity: 0.12

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"

      WlrLayershell.namespace: "lunav0-livebg"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Empty input region: clicks, drags and scrolls pass straight through to
      // the desktop below. Without this the layer would swallow every click on
      // the wallpaper.
      mask: Region {}

      Item {
        anchors.fill: parent
        opacity: root.intensity

        Repeater {
          model: root.paletteColors.length

          Shape {
            id: blob
            required property int index

            readonly property color tint: root.paletteColors[index]
            // Spread the blobs across the screen and give each a different
            // drift period, so the pattern never repeats on a short cycle.
            readonly property real baseX: panel.width * (0.15 + 0.7 * (index / Math.max(1, root.paletteColors.length - 1)))
            readonly property real baseY: panel.height * (index % 2 === 0 ? 0.35 : 0.65)
            readonly property real radius: Math.max(panel.width, panel.height) * 0.38

            anchors.fill: parent
            asynchronous: true
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: false

            property real driftX: 0
            property real driftY: 0

            // Long, prime-ish periods so the blobs fall out of phase with each
            // other instead of pulsing together.
            NumberAnimation on driftX {
              from: -panel.width * 0.12; to: panel.width * 0.12
              duration: 47000 + blob.index * 6100
              easing.type: Easing.InOutSine
              loops: Animation.Infinite
              running: true
            }
            SequentialAnimation on driftY {
              loops: Animation.Infinite
              running: true
              NumberAnimation {
                from: -panel.height * 0.10; to: panel.height * 0.10
                duration: 61000 + blob.index * 7300
                easing.type: Easing.InOutSine
              }
              NumberAnimation {
                from: panel.height * 0.10; to: -panel.height * 0.10
                duration: 61000 + blob.index * 7300
                easing.type: Easing.InOutSine
              }
            }

            ShapePath {
              strokeColor: "transparent"
              fillGradient: RadialGradient {
                centerX: blob.baseX + blob.driftX
                centerY: blob.baseY + blob.driftY
                centerRadius: blob.radius
                focalX: centerX
                focalY: centerY
                GradientStop { position: 0.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 1.0) }
                GradientStop { position: 0.55; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.35) }
                GradientStop { position: 1.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.0) }
              }
              startX: 0; startY: 0
              PathLine { x: panel.width; y: 0 }
              PathLine { x: panel.width; y: panel.height }
              PathLine { x: 0; y: panel.height }
              PathLine { x: 0; y: 0 }
            }
          }
        }
      }
    }
  }
}
