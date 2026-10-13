-- Ported from bindings.conf (Omarchy 3).
--
-- Quattro loads Omarchy's defaults before this file, so every key that already
-- has a default binding must be hl.unbind()-ed before it is re-bound. Keys that
-- Quattro already binds the way this setup wants them are NOT repeated here --
-- SUPER+SHIFT+F (nautilus), SUPER+SHIFT+B (browser), SUPER+SHIFT+ALT+B (browser
-- private), SUPER+SHIFT+N (editor), SUPER+SHIFT+D (lazydocker),
-- SUPER+SHIFT+O (obsidian) and SUPER+SHIFT+Y (YouTube) are all defaults now.

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

-- Was: SUPER+SHIFT+M -> Spotify.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", { webapp = "https://music.youtube.com/" })

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
o.bind("SUPER + CTRL + M", "WhatsApp", { webapp = "https://web.whatsapp.com/", focus = true })

-- SUPER+B used to peek the auto-hidden waybar, which Quattro's always-on shell
-- bar replaces. Repurposed to toggle bar transparency -- the nearest equivalent
-- of "get it out of the way".
o.bind("SUPER + B", "Bar transparency", "omarchy bar transparent toggle")

-- Toggle breathing vs rotating window border.
o.bind("SUPER + ALT + B", "Border effect", "border-breathe")

-- ---------------------------------------------------------------------------
-- Workspaces
--
-- Workspaces 1-10 live on HDMI-A-1 (Samsung, above); 11-20 live on DP-2 (LG
-- ultrawide, main).
--   SUPER + n          -> switch to workspace n           (Quattro default)
--   SUPER + SHIFT + n  -> move window to n, silently      (Quattro follows; overridden)
--   SUPER + CTRL + n   -> switch to workspace 10 + n
--   SUPER + ALT + n    -> move window to 10 + n, silently
-- ---------------------------------------------------------------------------

for n = 1, 10 do
  local key = "code:" .. tostring(n + 9)
  local upper = tostring(n + 10)

  -- Quattro binds this to "move and follow"; this setup wants it silent.
  hl.unbind("SUPER + SHIFT + " .. key)
  o.bind("SUPER + SHIFT + " .. key, "Move window silently to workspace " .. n,
    hl.dsp.window.move({ workspace = tostring(n), follow = false }))

  -- Was Quattro's silent-move; freed up so SUPER+ALT can address 11-20.
  hl.unbind("SUPER + SHIFT + ALT + " .. key)

  -- Quattro binds SUPER+ALT+1..5 to "select window n in group".
  hl.unbind("SUPER + ALT + " .. key)
  o.bind("SUPER + ALT + " .. key, "Move window silently to workspace " .. upper,
    hl.dsp.window.move({ workspace = upper, follow = false }))

  o.bind("SUPER + CTRL + " .. key, "Switch to workspace " .. upper,
    hl.dsp.focus({ workspace = upper }))
end

for n = 1, 10 do
  hl.workspace_rule({ workspace = tostring(n), monitor = "HDMI-A-1" })
end

for n = 11, 20 do
  hl.workspace_rule({ workspace = tostring(n), monitor = "DP-2" })
end
