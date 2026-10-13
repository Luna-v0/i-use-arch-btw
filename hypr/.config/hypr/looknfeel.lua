-- Ported from looknfeel.conf (Omarchy 3).

hl.config({
  decoration = {
    -- Round window corners.
    rounding = 8,
  },
})

-- Window opacity. Quattro applies its own opacity through a window rule in
-- default/hypr/windows.lua (`o.window({ tag = "default-opacity" }, ...)`)
-- rather than decoration.active_opacity, and that rule is evaluated before this
-- file loads. Setting decoration.active_opacity here would therefore be
-- silently overridden -- a later rule is what actually wins.
o.window(".*", { opacity = "0.95 0.87" })

-- Tone the transparency down on the TV (HDMI-A-1). At TV viewing distance the
-- 0.95/0.87 translucency above -- with the animated background showing through
-- it -- makes text noticeably harder to read, so the focused window there is
-- fully opaque and the unfocused one only slightly dimmed.
--
-- There is no `monitor` MATCH condition in Hyprland window rules (monitor
-- exists only as an action, setting where a window opens). `workspace` accepts
-- a workspace selector though, and `m[<output>]` selects every workspace on
-- that output -- so this tracks the monitor itself rather than hardcoding the
-- 11-20 workspace numbers. Verified matching on this setup.
--
-- This must stay AFTER the global rule above: later rules win.
o.window({ workspace = "m[" .. TV .. "]" }, { opacity = "1.0 0.95" })

-- Window border: the six-stop wallpaper-palette gradient (from the theme's
-- generated hyprland.lua), held still at its 45deg angle. It used to rotate
-- via a `borderangle` loop, but that redraws every window border every frame
-- forever -- constant GPU work on the card the compositor shares with compute.
-- Toggle a "breathing" pulse with SUPER + ALT + B (border-breathe), or re-enable
-- rotation with: enabled = true, speed = 30, bezier = "linear", style = "loop".
hl.animation({ leaf = "borderangle", enabled = false })
