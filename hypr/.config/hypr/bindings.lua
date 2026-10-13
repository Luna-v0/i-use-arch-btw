-- Ported from bindings.conf (Omarchy 3).
--
-- Quattro loads Omarchy's defaults before this file, so every key that already
-- has a default binding must be hl.unbind()-ed before it is re-bound. Keys that
-- Quattro already binds the way this setup wants them are NOT repeated here --
-- SUPER+SHIFT+F (nautilus), SUPER+SHIFT+B (browser), SUPER+SHIFT+ALT+B (browser
-- private), SUPER+SHIFT+N (editor), SUPER+SHIFT+D (lazydocker),
-- SUPER+SHIFT+O (obsidian) and SUPER+SHIFT+Y (YouTube) are all defaults now.

-- NOTE: ghostty was briefly routed through the `igpu` wrapper to keep terminal
-- windows off the 4060 Ti. That produced an entirely black window: rendering on
-- the AMD iGPU works, but the resulting buffer cannot be imported for display by
-- the NVIDIA compositor. Reverted. See ~/.local/bin/igpu for the details.
local terminal = "ghostty"

-- ---------------------------------------------------------------------------
-- Terminals
-- ---------------------------------------------------------------------------

-- Was: SUPER+RETURN -> Quattro's generic terminal launcher (foot).
hl.unbind("SUPER + RETURN")
-- `new-session -A` attaches to "main" if it exists and creates it otherwise.
-- The old `tmux a -t main` failed outright whenever the session was gone, and
-- the terminal closed the instant it opened.
o.bind("SUPER + RETURN", "Terminal", o.launch(
  terminal .. ' --working-directory="$(omarchy-cmd-terminal-cwd)" -e tmux new-session -A -s main'
))

-- Was: SUPER+SHIFT+RETURN -> Browser. In the Omarchy 3 config this key was
-- bound twice (Browser, then Terminal) and the last bind won, so a plain
-- terminal is what it actually did. That behaviour is preserved here; the
-- browser is still on SUPER+SHIFT+B.
hl.unbind("SUPER + SHIFT + RETURN")
o.bind("SUPER + SHIFT + RETURN", "Terminal (plain)", o.launch(
  terminal .. ' --working-directory="$(omarchy-cmd-terminal-cwd)"'
))

-- Was: SUPER+ALT+RETURN -> omarchy-launch-terminal-tmux (attaches session "Work").
hl.unbind("SUPER + ALT + RETURN")
o.bind("SUPER + ALT + RETURN", "Tmux", o.launch(
  'xdg-terminal-exec --dir="$(omarchy-cmd-terminal-cwd)" tmux new'
))

-- Was: SUPER+ALT+SHIFT+F -> Quattro's nautilus-cwd launcher.
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", o.launch(
  'nautilus --new-window "$(omarchy-cmd-terminal-cwd)"'
))

-- ---------------------------------------------------------------------------
-- Applications and web apps
-- ---------------------------------------------------------------------------

-- Music and WhatsApp open in their own Chromium profiles, the same ones
-- autostart uses, so they stay logged in (see webapps.lua).
local webapps = require("hypr.webapps")

-- Was: SUPER+SHIFT+M -> Spotify.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", webapps.launch("ytmusic"))

-- Was: SUPER+SHIFT+A -> ChatGPT.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Gemini", { webapp = "https://gemini.google.com" })

-- Was: SUPER+SHIFT+C -> HEY Calendar.
hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://calendar.google.com/", focus = true })

-- Was: SUPER+CTRL+P -> Quattro's power menu. Moved to pacman here, matching the
-- Omarchy 3 setup. The power menu is still reachable from the Omarchy menu
-- (SUPER+SPACE); swap this key if you would rather keep the Quattro default.
hl.unbind("SUPER + CTRL + P")
o.bind("SUPER + CTRL + P", "Package (pacman)", { tui = "omarchy-pkg-install" })

-- Unbound in Quattro's defaults, so these need no unbind.
o.bind("SUPER + SHIFT + T", "Activity", { tui = "btop" })
o.bind("SUPER + SHIFT + I", "Claude", { webapp = "https://claude.ai" })
o.bind("SUPER + CTRL + Y", "AUR (yay)", { tui = "omarchy-pkg-aur-install" })
o.bind("SUPER + CTRL + M", "WhatsApp", webapps.launch_sole("whatsapp", "WhatsApp"))

-- Quattro's own WhatsApp key would open the default (logged-out) profile.
hl.unbind("SUPER + SHIFT + ALT + G")
o.bind("SUPER + SHIFT + ALT + G", "WhatsApp", webapps.launch_sole("whatsapp", "WhatsApp"))

-- SUPER+B used to peek the auto-hidden waybar, which Quattro's always-on shell
-- bar replaces. Repurposed to toggle bar transparency -- the nearest equivalent
-- of "get it out of the way".
o.bind("SUPER + B", "Bar transparency", "omarchy bar transparent toggle")

-- Toggle breathing vs static window border.
o.bind("SUPER + ALT + B", "Border effect", "border-breathe")

-- Omarchy's background switcher only lists the active theme's backgrounds, and
-- the dynamic theme only ever holds one. Pick from the whole wallpaper folder
-- instead; each image's palette is precomputed, so the theme follows at once.
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Wallpaper + theme picker", "wallpaper-pick")

-- Switch the dictation model between fast (small.en) and accurate
-- (large-v3-turbo, for technical speech). The regular dictation keys
-- (SUPER+CTRL+X toggle, F9 push-to-talk) use whichever is active.
o.bind("SUPER + CTRL + SHIFT + X", "Dictation model (fast/accurate)", "voxtype-model")

-- Toggle the low-overhead gaming profile: no animations (this kills the
-- borderangle loop, which otherwise redraws every window border on every
-- frame), no rounding, opaque windows, tearing allowed, and the TV disabled so
-- only the ultrawide is composited. Fully reversible -- press again to restore.
o.bind("SUPER + CTRL + G", "Gaming mode", "gaming-mode")

-- PRINT alone opens Omarchy's interactive picker (freeform drag; a bare click
-- snaps to a window/monitor rect). That snap targets the *usable* area, which
-- excludes the bar's reserved strip -- so a click-snap on this setup yields
-- 3430x1408 rather than the full 3440x1440. This key skips the picker and
-- grabs the whole focused monitor, bar included.
o.bind("SHIFT + PRINT", "Screenshot (fullscreen)", "omarchy-capture-screenshot fullscreen")

-- PRINT sits behind Fn on this keyboard, which makes the default OCR key
-- (SUPER+CTRL+PRINT) a four-key chord. Same action, reachable without Fn.
o.bind("SUPER + ALT + O", "Extract text (OCR) from screenshot", "omarchy-capture-text")

-- ---------------------------------------------------------------------------
-- Workspaces
--
-- Workspaces 1-10 live on the LG ultrawide (main); 11-20 live on the LG TV
-- (above).
--   SUPER + n          -> switch to workspace n           (Quattro default)
--   SUPER + SHIFT + n  -> move window to n, silently      (Quattro follows; overridden)
--   SUPER + CTRL + n   -> switch to workspace 10 + n
--   SUPER + ALT + n    -> move window to 10 + n, silently
-- ---------------------------------------------------------------------------

-- Workspaces 11-20 live on CapsLock (remapped to Hyper = MOD3 in input.lua).
-- This mirrors the first decade exactly -- MOD3 is to 11-20 what SUPER is to
-- 1-10 -- and stays at two modifiers.
--
-- The previous scheme put them on SUPER+CTRL+<digit> and SUPER+ALT+<digit>,
-- which collided head-on with Quattro: SUPER+CTRL+1..9 is its "Bar panel N"
-- and SUPER+ALT+1..5 is "select window N in group". Both are left alone now.
for n = 1, 10 do
  local key = "code:" .. tostring(n + 9)
  local upper = tostring(n + 10)

  -- Quattro binds this to "move and follow"; this setup wants it silent.
  hl.unbind("SUPER + SHIFT + " .. key)
  o.bind("SUPER + SHIFT + " .. key, "Move window silently to workspace " .. n,
    hl.dsp.window.move({ workspace = tostring(n), follow = false }))

  o.bind("MOD3 + " .. key, "Switch to workspace " .. upper,
    hl.dsp.focus({ workspace = upper }))

  o.bind("MOD3 + SHIFT + " .. key, "Move window silently to workspace " .. upper,
    hl.dsp.window.move({ workspace = upper, follow = false }))
end

-- Workspaces 1-10 live on the ultrawide (SUPER + digit); 11-20 live on the TV
-- (CAPS + digit). This is the reverse of the original Omarchy 3 pinning, which
-- had 1-10 on the TV. UW / TV are the description selectors from monitors.lua.
for n = 1, 10 do
  hl.workspace_rule({ workspace = tostring(n), monitor = UW })
end

for n = 11, 20 do
  hl.workspace_rule({ workspace = tostring(n), monitor = TV })
end

-- Workspace rules only place a workspace when it is created. When a monitor
-- drops out (the TV on its flaky HDMI link, a DPMS power-off) Hyprland parks its
-- workspaces on the remaining screen, and they stay there after it returns.
-- Whenever a monitor comes back, send every existing workspace home.
local function rehome_workspaces()
  for _, ws in ipairs(hl.get_workspaces()) do
    local id = ws.id
    if id >= 1 and id <= 20 then
      hl.dispatch(hl.dsp.workspace.move({
        workspace = tostring(id),
        monitor = id <= 10 and UW or TV,
      }))
    end
  end
end

hl.on("monitor.added", rehome_workspaces)
