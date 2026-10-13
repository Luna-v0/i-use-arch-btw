# User override of omarchy's hyprland theme template.
# Emits a MULTI-STOP gradient border (from the palette) instead of the default
# single accent color, so the `borderangle` rotation animation in
# ~/.config/hypr/looknfeel.conf has a gradient to sweep around the window.
# Full-spectrum gradient (red-yellow-green-cyan-blue-magenta) so the rotating
# border sweeps through every palette hue.
$activeBorderColor = rgb({{ color1_strip }}) rgb({{ color3_strip }}) rgb({{ color2_strip }}) rgb({{ color6_strip }}) rgb({{ color4_strip }}) rgb({{ color5_strip }}) 45deg
$inactiveBorderColor = rgb({{ color0_strip }})

general {
    col.active_border = $activeBorderColor
    col.inactive_border = $inactiveBorderColor
}

group {
    col.border_active = $activeBorderColor
    col.border_inactive = $inactiveBorderColor
}
