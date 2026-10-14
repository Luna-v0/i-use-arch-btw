#!/usr/bin/env bash
# Undo apply.sh: remove every ufw rule it tagged, remove the qdrant
# DOCKER-USER restriction it may have added, and (on confirmation) put ufw
# back to inactive -- its state before apply.sh ever ran. Leaves sshd
# untouched (system/ssh-firewall/ owns that), and leaves any ufw rule or
# DOCKER-USER entry NOT tagged by apply.sh exactly as it found it.
#
# Run as root (sudo system/mercury-firewall/rollback.sh) on mercury, or
# piped in: ssh mercury 'sudo bash -s' < system/mercury-firewall/rollback.sh
# Pass --dry-run to only show what would be removed -- no sudo, no changes.
set -uo pipefail

TAG="dotfiles-mercury-firewall"
DEADMAN_UNIT="mercury-firewall-deadman"
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

INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

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
  if [ -n "$dns" ]; then echo "$dns"; else hostname 2>/dev/null || echo "this-host"; fi
}
SSH_TARGET="$(detect_ssh_target)"
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"

say "Dead-man timer"
if systemctl list-timers --all 2>/dev/null | grep -q "$DEADMAN_UNIT"; then
  info "Found: ${DEADMAN_UNIT}.timer -- would stop it (apply.sh's own safety net, no longer needed once rolled back)."
else
  info "None running (already fired, already cancelled, or apply.sh was never run)."
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

say "qdrant DOCKER-USER rule"
if command -v iptables >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    iptables -S DOCKER-USER 2>/dev/null | grep -- "--comment $TAG" || info "None found."
  else
    info "(run as root to inspect DOCKER-USER; this needs root even to read)"
  fi
else
  info "iptables not found."
fi

say "ufw ruleset state"
info "Current (/etc/ufw/ufw.conf): $(grep -E '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null || echo '<not found>'). apply.sh sets this to yes; it was 'no' before."

if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run -- nothing changed."
  exit 0
fi

echo
read -r -p "Remove the tagged ufw rules and the qdrant DOCKER-USER rule above? [y/N] " ans
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
  info "Nothing changed."
  exit 0
fi

say "Stopping the dead-man timer, if still armed"
systemctl stop "${DEADMAN_UNIT}.timer" "${DEADMAN_UNIT}.service" 2>/dev/null || true

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
  fi
else
  info "ufw not installed, skipping."
fi

say "Removing the qdrant DOCKER-USER rule"
if command -v iptables >/dev/null 2>&1; then
  # iptables has no "delete by comment" -- delete the exact rule spec
  # repeatedly until none match (apply.sh never inserts it twice, but this
  # is idempotent either way).
  removed=0
  while read -r line; do
    [ -z "$line" ] && continue
    # line looks like: -A DOCKER-USER -d 172.x.x.x/32 -p tcp -m multiport --dports 6333,6334 -j DROP -m comment --comment TAG-qdrant-restrict
    rule="${line#-A DOCKER-USER }"
    # shellcheck disable=SC2086
    if iptables -D DOCKER-USER $rule 2>/dev/null; then
      removed=$((removed + 1))
    fi
  done < <(iptables -S DOCKER-USER 2>/dev/null | grep -- "--comment ${TAG}-qdrant-restrict")
  if [ "$removed" -gt 0 ]; then
    info "Removed $removed matching DOCKER-USER rule(s). qdrant is reachable via Docker's normal forwarding path again (host-local + whatever ufw/network policy otherwise applies)."
  else
    info "No matching DOCKER-USER rule found."
  fi
else
  info "iptables not found, skipping."
fi

say "ufw service"
echo
read -r -p "Also run 'ufw disable' to fully restore the pre-apply.sh state (ufw was inactive before)? [y/N] " ans2
if [[ "$ans2" =~ ^[Yy]$ ]]; then
  ufw disable
  info "ufw disabled."
else
  info "Left ufw as-is ($(grep -E '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null || echo unknown)) with default-deny-incoming and whatever rules remain -- review with 'ufw status verbose'."
fi

say "Done"
info "Current session was never touched by apply.sh or this script; verify a fresh connection still works:"
info "    ssh $TARGET_USER@$SSH_TARGET"
