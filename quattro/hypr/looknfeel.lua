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
o.window(".*", { opacity = "0.90 0.80" })

-- Animated window border -- the gradient continuously rotates around the
-- outline. Anti-burn (the border is never static) and it matches the wallpaper
-- palette, since the border colors come from the theme's generated
-- hyprland.lua gradient.
-- Toggle a "breathing" pulse instead with SUPER + ALT + B (border-breathe).
-- speed: lower = faster rotation (30 ~= 3s/turn; 100 ~= 10s).
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "linear", style = "loop" })
