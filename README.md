# 🏠 Omarchy Dotfiles

Personal dotfiles for an Arch Linux setup running **Omarchy 4 ("Quattro")** with **Hyprland 0.56** (Lua config).

## 🛠️ Tools & Configurations

Stow packages (each mirrors its path under `~`):

| Directory | Description |
|-----------|-------------|
| `hypr/` | Hyprland Lua config: `hyprland.lua` loads Omarchy's defaults, then `monitors`, `input`, `bindings`, `looknfeel`, `autostart`, `gpu`, `webapps`; also Hyprsunset |
| `omarchy/` | Omarchy 4: `shell.json` (omarchy-shell bar), `plugins/lunav0.*` shell plugins, hooks, themed templates, themes (`dynamic`, `osaka-jade-custom`) |
| `nvim/` | Neovim with LazyVim (typst, auto-save, OSC52 clipboard over SSH) |
| `tmux/` | Tmux with TPM. Only `tpm` is a submodule; install the plugins with `prefix + I` |
| `xonsh/` | xonsh interactive shell (runs inside tmux panes — see `xonsh/README.md`) |
| `ghostty/` | Ghostty terminal emulator |
| `starship.toml/` | Starship shell prompt |
| `bin/` | `~/.local/bin` scripts: dynamic theme and wallpaper, GPU switching, local LLM helpers, sysmon |
| `systemd/` | User systemd services and their enablement links |
| `opencode/` | opencode with a local Ollama provider |
| `antigravity/` | `local-subagent` plugin under `~/.gemini/config/plugins` |
| `applications/` | `~/.local/share/applications` launchers for WhatsApp, Youtube Music and Discord, pinned to their per-profile Chromium `--user-data-dir` (see `hypr/.config/hypr/webapps.lua`) so relaunching from the app grid doesn't fall back to the default, logged-out profile |

Not stow packages:

| Directory | Description |
|-----------|-------------|
| `quattro/` | Omarchy 3 → 4 migration kit. `quattro/legacy/` keeps the retired waybar, walker, mako, swayosd, hyprlock and hypridle configs |
| `ollama/` | Modelfile for `ollama create` |
| `scripts/` | Custom Python scripts (e.g., `hyprtui.py` for Hyprland TUI) |
| `system/` | Standalone `sudo`-run host-hardening scripts, one subdirectory per concern (e.g. `ssh-firewall/`). Not stowed; run directly, never applied automatically |

## ⚠️ Machine-Specific Files

These files contain hardware-specific configurations and **need to be adjusted per machine**:

| File | Purpose |
|------|---------|
| `hypr/.config/hypr/monitors.lua` | Monitor layout, resolution, and scaling |
| `hypr/.config/hypr/gpu.lua` | VA-API/GLX routing for an AMD iGPU + NVIDIA dGPU |
| `applications/.local/share/applications/{WhatsApp,Youtube Music,Discord}.desktop` | `--user-data-dir` is the absolute `$HOME` path baked in at write time (Exec= can't expand `~` or `$HOME`); update it for a different username |

## 📦 Installation

This repo uses [Omadot](https://github.com/tomhayes/omadot) for symlink management. From the dotfiles directory:

```bash
omadot put --all --exclude=quattro,ollama,scripts   # symlink every package into ~
omadot put xonsh         # …or a single package
omadot list             # list available packages
```

### System packages (pacman)

Most configs assume their program is installed. The shell setup in particular needs:

```bash
sudo pacman -S --needed fish zoxide fzf tmux
```

`fish` powers the `fish_completer` xontrib; `zoxide`/`fzf` back xonsh completions and
directory jumping. See [`xonsh/README.md`](xonsh/README.md) for the full xonsh +
tmux shell setup (including the `~/.local/xonsh-env` bootstrap, which is not a pacman
package).

