-- Ported from monitors.conf (Omarchy 3). See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- 1x setup: LG ultrawide (main) + Samsung 1080p stacked above it, left edges aligned.
hl.env("GDK_SCALE", "1")

-- Main: LG ultrawide at native 3440x1440@160Hz, primary at origin.
hl.monitor({ output = "DP-2", mode = "3440x1440@159.96", position = "0x0", scale = 1 })

-- Second: Samsung 1080p directly above, left-aligned (flip to 0x1440 to put it below).
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@59.94", position = "0x-1080", scale = 1 })
