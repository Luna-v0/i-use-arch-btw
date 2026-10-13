import QtQuick
import Quickshell
import qs.Commons

// Drifts the bar's foreground colour slowly through the active palette, so the
// topbar icons breathe the same colours as the lunav0.livebg aurora.
//
// This deliberately does NOT fork the bar. Bar.qml resolves icon colour as
// `barForeground -> themeForeground -> Color.bar.text`, and Color.bar.text is a
// writable property consumed by exactly two lines, both of them bar foreground.
// Driving that one property recolours every widget -- first-party and mine --
// and leaves the 1823-line bar engine on the packaged copy, so Omarchy updates
// still land.
Scope {
  id: root

  // Same six-stop wallpaper-derived gradient the aurora and the Hyprland
  // active border use. Re-evaluates on theme swap because Color.shellValues is
  // reassigned wholesale when the theme changes.
  readonly property var paletteColors: {
    const raw = Color.shellValues["hyprland.active-border"] || ""
    const tokens = String(raw).trim().split(/\s+/).filter(t => t && !t.match(/^-?\d+(?:\.\d+)?deg$/))
    return tokens.length >= 2 ? tokens : [Color.foreground]
  }

  // Seconds for one full trip through the palette. Long on purpose: this should
  // read as the bar slowly breathing, not as a colour cycle demanding attention.
  readonly property int cycleSeconds: 180

  // How far toward the palette colour to pull the icons. 1.0 is the raw palette
  // colour; lower values keep more of the theme's own foreground so icons stay
  // obviously legible. This is the knob to turn.
  readonly property real strength: 0.85

  // The palette's ANSI colours sit around 50-60% brightness, which is fine for
  // a window border but drops bar icons from roughly 13:1 contrast against the
  // bar background to about 4:1. Take hue and saturation from the palette but
  // hold brightness up, so the icons change colour without getting harder to
  // read. Lower this if you want moodier, dimmer icons.
  readonly property real minBrightness: 0.86

  property real phase: 0

  function mix(a, b, f) {
    const ca = Qt.color(a)
    const cb = Qt.color(b)
    return Qt.rgba(ca.r + (cb.r - ca.r) * f,
                   ca.g + (cb.g - ca.g) * f,
                   ca.b + (cb.b - ca.b) * f, 1)
  }

  // Keep the hue and saturation, lift the brightness to the legibility floor.
  function brighten(c) {
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue,
                   c.hsvSaturation,
                   Math.max(c.hsvValue, root.minBrightness),
                   1)
  }

  function paletteAt(p) {
    const cols = root.paletteColors
    const n = cols.length
    if (n === 0) return Color.foreground
    if (n === 1) return Qt.color(cols[0])

    const scaled = p * n
    const i = Math.floor(scaled) % n
    const j = (i + 1) % n
    return root.mix(cols[i], cols[j], scaled - Math.floor(scaled))
  }

  // Stepping every 400ms rather than every frame: Bar.qml already runs a 420ms
  // ColorAnimation behaviour on barForeground, so each step is smoothed into
  // the next and the result is continuous drift for ~2.5 property writes a
  // second instead of 160.
  Timer {
    interval: 400
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.phase = (root.phase + interval / (root.cycleSeconds * 1000)) % 1
      Color.bar.text = root.brighten(root.mix(Color.foreground, root.paletteAt(root.phase), root.strength))
    }
  }
}
