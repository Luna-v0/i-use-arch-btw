-- Ported from autostart.conf (Omarchy 3).

-- Start the "main" tmux session at login so plugins load and SUPER+RETURN has
-- something to attach to. Previously this created a session called "_init"
-- while the keybinding attached to "main", so the two never met.
o.exec_on_start("tmux has-session -t main 2>/dev/null || tmux new-session -d -s main")

o.launch_on_start("slack")
o.launch_on_start("Telegram")
o.exec_on_start("hyprshell run")

-- Chromium web-apps, each in its own profile (see webapps.lua for why). The
-- sleeps are NOT for race safety -- separate profiles handle that -- they
-- serialize launches so each window's class is set before the next maps,
-- which is what lets the per-class workspace rules below land.
local webapps = require("hypr.webapps")

o.exec_on_start(webapps.launch("ytmusic"))
o.exec_on_start("sh -c " .. o.shell_quote("sleep 1.5; " .. webapps.launch("whatsapp")))
o.exec_on_start("sh -c " .. o.shell_quote("sleep 3; " .. webapps.launch("discord")))

-- Anti-burn: pull a fresh ultrawide wallpaper + derive the whole palette from
-- it each boot. No-ops offline.
--
-- The Omarchy 3 version also ran `pkill -x waybar` to leave the bar hidden.
-- Quattro's bar is part of the always-running shell and is not killable that
-- way; SUPER+B now toggles bar transparency instead (see bindings.lua).
o.exec_on_start("dynamic-theme")

-- Build palettes for any wallpapers added since last boot (incremental, niced),
-- so the SUPER+CTRL+SPACE picker applies precomputed themes.
o.exec_on_start("wallpaper-precompute")

-- Window rules: pin chat/media apps to their workspaces.
o.window(".*iscord.*", { workspace = "13" })
o.window("[Ss]lack", { workspace = "19" })
o.window(".*elegram.*", { workspace = "14" })
o.window(".*hatsapp.*", { workspace = "15" })
o.window(".*usic\\.youtube.*", { workspace = "16" })
