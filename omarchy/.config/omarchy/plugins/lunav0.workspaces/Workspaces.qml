import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Highest workspace this setup uses. Stock capped at 10, which is why
  // workspaces 11-20 never appeared.
  readonly property int maxWorkspace: 20

  // Chip width. Stock used a single value sized for one digit, which leaves
  // two-digit labels (11-20, shown whenever the list spans both decades)
  // looking cramped. Widen only those.
  readonly property int slotWidth: 20
  readonly property int wideSlotWidth: 28

  function workspaceIds() {
    var ids = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= root.maxWorkspace && ids.indexOf(id) === -1) ids.push(id)
    }

    // Keep the first five of whichever decade is focused present even when
    // empty, matching stock behaviour of always offering 1-5. Following the
    // focused workspace means a monitor showing 11-20 gets an 11-15 baseline
    // instead of a 1-5 one that belongs to the other monitor.
    var decade = 0
    var fw = Hyprland.focusedWorkspace
    if (fw && fw.id > 0 && fw.id <= root.maxWorkspace) decade = Math.floor((fw.id - 1) / 10)
    for (var b = 1; b <= 5; b++) {
      var base = decade * 10 + b
      if (ids.indexOf(base) === -1) ids.push(base)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  // Within one decade the last digit is also the key you press (workspace 13
  // is CAPS+3), so show that. When the list spans both decades -- which it
  // does while a monitor is unplugged and its workspaces fall through to the
  // remaining one -- show full ids, or 3 and 13 would both render as "3".
  readonly property bool singleDecade: {
    var ids = root.workspaceIds()
    if (ids.length === 0) return true
    var d = Math.floor((ids[0] - 1) / 10)
    for (var i = 1; i < ids.length; i++) {
      if (Math.floor((ids[i] - 1) / 10) !== d) return false
    }
    return true
  }

  function workspaceLabel(id) {
    if (!root.singleDecade) return String(id)
    return (id % 10 === 0) ? "0" : String(id % 10)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : root.workspaceLabel(modelData)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical
          ? root.barSize
          : Style.space(root.workspaceLabel(modelData).length > 1 ? root.wideSlotWidth : root.slotWidth)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
