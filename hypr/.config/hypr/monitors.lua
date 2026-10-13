-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- DP-2      LG ULTRAWIDE 3440x1440  -- "UW", primary, workspaces 1-10
-- HDMI-A-1  LG TV 1920x1080         -- "NUW", secondary, workspaces 11-20
--
-- Outputs are matched by EDID description, not connector name: the connector
-- names change when the cables move between the RTX card and the motherboard
-- (iGPU) ports, the descriptions don't. UW and TV below are reused by
-- bindings.lua and looknfeel.lua.
UW = "desc:LG Electronics LG ULTRAWIDE 606AZLWA5120"
TV = "desc:LG Electronics LG TV 0x01010101"
hl.env("GDK_SCALE", "1")

-- Primary: ultrawide at native resolution, at the origin.
hl.monitor({ output = UW, mode = "3440x1440@159.96", position = "0x0", scale = 1 })

-- Secondary: the TV scaled up so text renders larger.
--
-- Only a few scales divide 1920x1080 into whole logical pixels -- 1.2, 1.25,
-- 1.5, 1.6, 2.0. Anything else (1.3, 1.4, 1.75...) leaves fractional sizes that
-- Hyprland renders soft. 1.25 gives a logical 1536x864.
--
-- Position is in LOGICAL pixels. Centring the 1536-wide TV over the 3440-wide
-- ultrawide puts its left edge at (3440 - 1536) / 2 = 952, and sitting it
-- directly above means y = -864 (its logical height).
hl.monitor({ output = TV, mode = "1920x1080@59.94", position = "952x-864", scale = 1.25 })
