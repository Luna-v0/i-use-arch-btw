# Porting this setup to Omarchy 4 (Quattro)

Prepared against [v4.0.0](https://github.com/basecamp/omarchy/releases/tag/v4.0.0),
verified against the v4.0.0 source tree and the Hyprland 0.56.2 Lua stubs already
installed at `/usr/share/hypr/stubs/hl.meta.lua`.

## What Quattro actually changes

Two independent rewrites land at once:

1. **The desktop shell.** Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle,
   swaybg and polkit-gnome are replaced by one Quickshell process
   (`omarchy-shell`), configured through `~/.config/omarchy/shell.json` and
   extended with plugins under `~/.config/omarchy/plugins/`.
2. **Hyprland config moves from `.conf` to Lua** for 0.56 compatibility. The
   upgrade installs fresh `~/.config/hypr/*.lua` and leaves the old `.conf`
   files on disk, unread, purely as reference.

Plus: Omarchy itself moves from a git checkout at `~/.local/share/omarchy` to
pacman-managed files under `/usr/share/omarchy`, generated theme state moves
from `~/.config/omarchy/current` to `~/.local/state/omarchy/current`, and
Wi-Fi moves from iwd to NetworkManager.

## How this setup fares

| Thing | Verdict |
|---|---|
| Dynamic NASA/wallhaven theming (`dynamic-theme`, `wallpaper-fetch`, `wallpaper-palette`) | **Survives.** `colors.toml` is still the input and Quattro maps `colorN` → semantic names both ways. It gets *better*: more surfaces are generated from the palette. |
| `~/.config/omarchy/themed/*.tpl` user template overrides | **Survives**, same `{{ key }}` / `{{ key_strip }}` syntax, user templates still beat built-ins. |
| Gradient rotating window border | **Survives**, via a cleaner route — see below. |
| Hyprland keybindings, monitors, input, autostart, window rules | **Hand-port to Lua.** Already done in `hypr/*.lua` here. |
| Waybar config, `style.css`, custom cpu/gpu-temp scripts | **Gone.** Needs re-authoring as shell plugins (QML). |
| Two bars, DP-2 top + HDMI-A-1 bottom | **No stock equivalent.** `bar.position` is a single global value. |
| `waybar-peek` (hide bar, peek on SUPER+B) | **Gone.** Rebound to `omarchy bar transparent toggle`. |
| `border-breathe` | **Patched.** `hyprctl keyword` is rejected by the Lua parser; it now uses `hyprctl eval` + `hl.config()` and auto-detects which to use. |
| `tmux-palette` | **Patched** for the new state path. Quattro also ships `omarchy-theme-set-tmux`, so this is now optional. |
| walker / mako / swayosd configs | **Gone.** Retired to `legacy/`. |
| Saved Wi-Fi networks | **Lost** unless backed up — nothing converts `/var/lib/iwd`. |
| stow symlinks | Fine everywhere **except** `~/.config/omarchy/plugins/`, where `omarchy plugin validate` rejects symlinks. Use real files there. |

### The border gradient, done better

Omarchy 3 needed `themed/hyprland.conf.tpl` to emit a multi-stop gradient,
because the stock template only produced a single accent color. Quattro's
`hyprland.lua.tpl` reads a `hyprland_active_border` key straight from
`colors.toml` and understands gradient specs, so `wallpaper-palette` now writes:

```toml
hyprland_active_border = "color1 color3 color2 color6 color4 color5 45deg"
hyprland_inactive_border = "color8"
```

No template override needed, and the same gradient now also reaches the shell's
notification, popup and lock-screen borders via `shell.toml`. Verified: this
renders to the identical six-stop gradient the old template produced.

(`color0` is *not* usable for the inactive border — Quattro's color resolver
forces `color0` to equal `background`, which would make inactive borders
invisible. Hence `color8`.)

## Runbook

```bash
bash ~/.dotfiles/quattro/preflight.sh    # capture state, unstow retired packages
# ...run the two sudo commands it prints (snapper snapshot + iwd backup)

omarchy update                            # onto latest 3.x
omarchy update                            # then: "Omarchy to Quattro"
# reboot

bash ~/.dotfiles/quattro/postflight.sh    # install ported Lua, retire dead configs, re-theme
```

`postflight.sh` moves retired files into `quattro/legacy/` rather than deleting
them, so `git status` afterwards is a readable diff of exactly what changed.

## Notes on the ported bindings

Quattro loads its defaults *before* your `bindings.lua`, so any key that already
has a default binding needs `hl.unbind()` first. Keys re-bound here because
Quattro claims them:

| Key | Quattro default | Restored to |
|---|---|---|
| `SUPER+RETURN` | generic terminal (foot) | ghostty + `tmux a -t main` |
| `SUPER+SHIFT+RETURN` | Browser | plain ghostty |
| `SUPER+ALT+RETURN` | tmux session "Work" | `xdg-terminal-exec … tmux new` |
| `SUPER+ALT+SHIFT+F` | nautilus-cwd | same, explicit |
| `SUPER+SHIFT+M` | Spotify | YouTube Music web app |
| `SUPER+SHIFT+A` | ChatGPT | Gemini |
| `SUPER+SHIFT+C` | HEY Calendar | Google Calendar |
| `SUPER+CTRL+P` | **Power menu** | pacman TUI |
| `SUPER+SHIFT+<n>` | move to workspace, follow | move silently |
| `SUPER+ALT+<n>` | select window *n* in group | move silently to workspace 10+*n* |

Two behaviours worth a second look:

- **`SUPER+CTRL+P` shadows Quattro's power menu.** Still reachable from the
  Omarchy menu on `SUPER+SPACE`. Change it if you'd rather keep the default.
- **`SUPER+SHIFT+RETURN` was bound twice** in the old `bindings.conf` (Browser,
  then Terminal). The last one won, so it opened a plain terminal — that is what
  the port preserves. The browser is still on `SUPER+SHIFT+B`.

Dropped because Quattro's defaults already do the same thing: `SUPER+SHIFT+F`,
`SUPER+SHIFT+B`, `SUPER+SHIFT+ALT+B`, `SUPER+SHIFT+N`, `SUPER+SHIFT+D`,
`SUPER+SHIFT+O`, `SUPER+SHIFT+Y`.

## Opacity gotcha

`decoration.active_opacity` no longer works the way it did. Quattro sets window
opacity through a rule in `default/hypr/windows.lua`
(`o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })`) which is
evaluated *before* your `looknfeel.lua`. Setting `decoration.active_opacity`
there is silently overridden. The port uses a later window rule instead:

```lua
o.window(".*", { opacity = "0.90 0.80" })
```

## Keyboard layout gotcha

Quattro's `default/hypr/input.lua` derives `kb_layout` from `/etc/vconsole.conf`.
This machine has `XKBLAYOUT=br` and `XKBMODEL=abnt2` but **no `XKBVARIANT`**, so
the `abnt2` variant would be dropped. `hypr/input.lua` here pins it explicitly,
along with `repeat_delay = 600` (Quattro defaults to 250) and the compose-only
Caps behaviour (Quattro adds `shift:both_capslock_cancel`).

## Still to do after the upgrade

- **Bar.** Pick one position for both monitors (`omarchy bar position top`).
  Re-author the custom `cpu-temp`, `gpu-temp` and `voxtype` modules as shell
  plugins — start from `omarchy plugin clone <id>` and edit under
  `~/.config/omarchy/plugins/` (real files, not stow symlinks).
  Old waybar sources are preserved in `legacy/waybar/`.
- **Wi-Fi.** Re-add saved networks through the shell's network panel.
- **Themes.** `themes/osaka-jade-custom/` still carries `waybar.css`,
  `swayosd.css`, `mako.ini`, `walker.css` and `hyprlock.conf` — all dead files
  now. Quattro generates the equivalents from `colors.toml`; deleting them is
  safe once you've confirmed the theme still looks right.
