# 🏠 Omarchy Dotfiles

Personal dotfiles for an Arch Linux setup running **Hyprland** as the Wayland compositor.

## 🛠️ Tools & Configurations

| Directory | Description |
|-----------|-------------|
| `hypr/` | Hyprland compositor, Hyprlock, Hypridle, Hyprsunset |
| `nvim/` | Neovim with LazyVim |
| `tmux/` | Tmux with TPM plugins (resurrect, continuum, yank) |
| `ghostty/` | Ghostty terminal emulator |
| `waybar/` | Waybar status bar |
| `walker/` | Walker application launcher |
| `mako/` | Mako notification daemon |
| `starship.toml/` | Starship shell prompt |
| `swayosd/` | SwayOSD on-screen display |
| `omarchy/` | Omarchy themes & branding |
| `scripts/` | Custom Python scripts (e.g., `hyprtui.py` for Hyprland TUI) |
| `systemd/` | User systemd services |

## ⚠️ Machine-Specific Files

These files contain hardware-specific configurations and **need to be adjusted per machine**:

| File | Purpose |
|------|---------|
| `hypr/.config/hypr/monitors.conf` | Monitor layout, resolution, and scaling |

## 📦 Installation

This repo uses [Omadot](https://github.com/tomhayes/omadot) for symlink management. From the dotfiles directory:

