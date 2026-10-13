#!/usr/bin/env bash
# Run BEFORE upgrading to Omarchy 4 (Quattro).
#
# Captures the state the upgrade destroys or moves, and unstows the four config
# packages Quattro retires so the upgrade does not leave dangling stow symlinks
# behind. Everything it touches is either read-only or already committed to git.
#
# The two things it CANNOT do without sudo are printed at the end -- run those
# yourself before rebooting into the upgrade.
set -uo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
OUT="$DOTFILES/quattro/preflight-$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUT"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

say "Capturing current state -> $OUT"
{
  echo "# omarchy version"; omarchy version 2>/dev/null || cat ~/.local/share/omarchy/version
  echo; echo "# current theme"; omarchy theme current 2>/dev/null
  echo; echo "# hyprland"; hyprctl version 2>/dev/null | head -2
  echo; echo "# monitors"; hyprctl monitors 2>/dev/null | grep -E '^Monitor|^\s+(description|[0-9]+x[0-9]+)'
} >"$OUT/system.txt" 2>&1

systemctl --user list-unit-files --state=enabled --no-pager >"$OUT/user-units-enabled.txt" 2>&1
systemctl --user list-units --type=service --no-pager >"$OUT/user-units-running.txt" 2>&1
omarchy menu keybindings --print >"$OUT/keybindings-v3.txt" 2>&1 || true
pacman -Qqe >"$OUT/pacman-explicit.txt" 2>&1

# The generated theme state is gitignored and moves to ~/.local/state during the
# upgrade. Keep a copy so a bad palette regeneration is diagnosable.
cp -a "$HOME/.config/omarchy/current" "$OUT/omarchy-current" 2>/dev/null || true

say "Checking the dotfiles repo is clean"
if [ -n "$(git -C "$DOTFILES" status --porcelain)" ]; then
  git -C "$DOTFILES" status --short
  echo
  echo "  ^ Commit or stash these first. The upgrade writes into the stowed"
  echo "    tree (new hypr/*.lua, omarchy/shell.json, branding files), and you"
  echo "    want that diff readable afterwards."
  exit 1
fi
echo "  clean."

say "Unstowing the packages Quattro retires"
# The upgrade does `mv ~/.config/<name> ~/.config/<name>.<...>.bak` on each of
# these. With stow that moves the SYMLINK, not the content -- the repo files are
# safe either way -- but it leaves a stale link pointing into the repo and
# confuses `stow -R` later. Removing them up front is cleaner.
for pkg in waybar walker mako swayosd; do
  if [ -L "$HOME/.config/$pkg" ]; then
    (cd "$DOTFILES" && stow -D "$pkg") && echo "  unstowed $pkg"
  else
    echo "  $pkg: not a stow symlink, skipping"
  fi
done

say "Manual steps that need sudo -- run these yourself"
cat <<'MANUAL'
  # 1. Snapshot the root subvolume. This machine is btrfs + snapper + limine,
  #    so a bad upgrade is recoverable from the boot menu.
  sudo snapper -c root create -d "pre-omarchy-quattro"

  # 2. Back up saved Wi-Fi networks. Quattro switches iwd -> NetworkManager and
  #    nothing converts /var/lib/iwd, so every saved network is gone after the
  #    reboot. Harmless to skip on a wired-only machine.
  sudo tar czf ~/iwd-profiles-backup.tar.gz -C /var/lib iwd
MANUAL

say "Then run the upgrade"
cat <<'UPGRADE'
  omarchy update            # get onto the latest 3.x first
  omarchy update            # then choose: Omarchy to Quattro
  # ...reboot, log in, then: bash ~/.dotfiles/quattro/postflight.sh
UPGRADE
