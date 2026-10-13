-- Ported from autostart.conf (Omarchy 3).

-- Start the "main" tmux session at login so plugins load and SUPER+RETURN has
-- something to attach to. Previously this created a session called "_init"
-- while the keybinding attached to "main", so the two never met.
o.exec_on_start("tmux has-session -t main 2>/dev/null || tmux new-session -d -s main")

o.launch_on_start("bitwarden-desktop")
o.launch_on_start("slack")
o.launch_on_start("Telegram")
o.exec_on_start("hyprshell run")

-- Chromium web-apps all share ONE profile. Launching several --app windows in
-- the same instant makes them race for the profile's SingletonLock; the losers
-- throw Chromium's native "Profile error occurred / profile could not be
-- opened" dialog. Fix: launch the first app, then wait until its Chromium owns
-- the profile (SingletonSocket exists). Once one instance owns the profile,
-- later launches hand off to it as windows and can never race -- no fixed
-- sleeps needed.
local await_chromium_profile =
  "bash -c 'until [ -e ~/.config/chromium/SingletonSocket ]; do sleep 0.3; done; %s'"

o.exec_on_start(o.launch_webapp("https://music.youtube.com/"))
o.exec_on_start(await_chromium_profile:format(o.launch_webapp("https://web.whatsapp.com/")))
o.exec_on_start(await_chromium_profile:format(
  o.launch_webapp_sole("discord", "https://discord.com/channels/@me")
))

-- Anti-burn: pull a fresh ultrawide wallpaper + derive the whole palette from
-- it each boot. No-ops offline.
--
-- The Omarchy 3 version also ran `pkill -x waybar` to leave the bar hidden.
-- Quattro's bar is part of the always-running shell and is not killable that
-- way; SUPER+B now toggles bar transparency instead (see bindings.lua).
o.exec_on_start("dynamic-theme")

-- Window rules: pin chat/media apps to their workspaces.
o.window("Bitwarden", { workspace = "9" })
o.window(".*iscord.*", { workspace = "13" })
o.window("[Ss]lack", { workspace = "19" })
o.window(".*hatsapp.*", { workspace = "14" })
o.window(".*elegram.*", { workspace = "14" })
o.window(".*usic\\.youtube.*", { workspace = "15" })
