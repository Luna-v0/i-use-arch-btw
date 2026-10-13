#!/usr/bin/env bash
# Undo apply.sh: remove the sshd hardening drop-in, and the tagged ufw rules
# if apply.sh was ever run with --allow-lan-ssh and/or --allow-lan-mdns (by
# default apply.sh touches no ufw rule, so there is usually nothing tagged
# here to remove). Leaves everything else (including any pre-existing
# tailscale0 SSH rule) untouched, since apply.sh never touches it either.
#
# Run as root (sudo system/ssh-firewall/rollback.sh). Pass --dry-run to only
# show what would be removed.
set -uo pipefail

TAG="dotfiles-ssh-firewall"
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-local-hardening.conf
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
  --dry-run) DRY_RUN=1 ;;
  -h | --help)
    echo "Usage: $0 [--dry-run]"
    exit 0
    ;;
  *)
    echo "Unknown option: $arg (try --help)" >&2
    exit 2
    ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '%s\n' "$*"; }
warn() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  warn "This changes system state and needs root. Run with sudo, or pass --dry-run to only inspect."
  exit 1
fi

# --- detect: this host's own name for the printed ssh command -- never hard-coded
detect_ssh_target() {
  local dns=""
  if command -v tailscale >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      dns="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null)"
    elif command -v python3 >/dev/null 2>&1; then
      dns="$(tailscale status --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("Self", {}).get("DNSName", ""))
except Exception:
    pass
' 2>/dev/null)"
    fi
  fi
  dns="${dns%.}"
  if [ -n "$dns" ]; then
    echo "$dns"
  else
    hostname 2>/dev/null || echo "this-host"
  fi
}
SSH_TARGET="$(detect_ssh_target)"

say "sshd drop-in"
if [ -f "$SSHD_DROPIN" ]; then
  info "Present: $SSHD_DROPIN (would remove)"
else
  info "Not present, nothing to remove."
fi

say "Tagged ufw rules"
if command -v ufw >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    ufw status numbered 2>/dev/null | grep "$TAG" || info "None found."
  else
    info "(run as root to list exact numbered rules; file-based check below)"
    grep -E "$TAG" /etc/ufw/user.rules /etc/ufw/user6.rules 2>/dev/null | sed -n 's/^.*### tuple ### //p' || info "None found."
  fi
else
  info "ufw not installed."
fi

if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run -- nothing changed."
  exit 0
fi

echo
read -r -p "Remove the sshd drop-in and the tagged ufw rules above? [y/N] " ans
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
  info "Nothing changed."
  exit 0
fi

say "Removing tagged ufw rules"
if command -v ufw >/dev/null 2>&1; then
  # Delete by number, highest first, so earlier numbers don't shift under us.
  mapfile -t nums < <(ufw status numbered 2>/dev/null | grep "$TAG" | grep -oE '^\[[0-9]+\]' | tr -d '[]' | sort -rn)
  if [ "${#nums[@]}" -eq 0 ]; then
    info "No tagged rules found to remove."
  else
    for n in "${nums[@]}"; do
      ufw --force delete "$n"
    done
    ufw reload
  fi
else
  info "ufw not installed, skipping."
fi

say "Removing sshd drop-in"
if [ -f "$SSHD_DROPIN" ]; then
  rm -f "$SSHD_DROPIN"
  if sshd -t; then
    systemctl reload sshd.service
    info "Removed and reloaded sshd. Password authentication and root login"
    info "are back to whatever they were before (this host's Arch defaults"
    info "disable keyboard-interactive auth but otherwise allow passwords)."
  else
    warn "sshd -t failed after removing the drop-in; NOT reloading sshd."
    warn "Inspect /etc/ssh/sshd_config and sshd_config.d/ before reloading by hand."
    exit 1
  fi
else
  info "Not present, nothing to remove."
fi

say "Done"
info "Current session was never touched; verify a fresh connection still works:"
info "    ssh \$USER@$SSH_TARGET"
