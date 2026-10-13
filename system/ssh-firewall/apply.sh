#!/usr/bin/env bash
# Turn off sshd password/root auth -- without ever risking a lockout.
#
# Run as root (sudo system/ssh-firewall/apply.sh). Pass --dry-run to only
# detect the current state and print the plan, without sudo and without
# changing anything.
#
# CORRECTED PREMISE: this host's ufw is already active, default-deny-incoming,
# and already has a tailscale0-only SSH allow rule. 3 weeks of `journalctl -u
# sshd` show 118/118 accepted sessions came from the tailnet; zero from the
# LAN. So by default this script changes NO ufw rules -- adding a LAN-scoped
# SSH/mDNS allow would only loosen an already-correct posture for access
# nobody uses. The two LAN rules exist, but only behind explicit opt-in flags
# (--allow-lan-ssh / --allow-lan-mdns), each printed with why it isn't on by
# default. The sshd hardening drop-in is the one thing this host is actually
# missing, so it's what runs by default.
#
# SECOND CORRECTION: the dead-man switch only proves SSH still works from
# whichever device you happen to confirm from. Over the last 30 days this
# host also had password logins from devices that have NEVER used a key here
# (not just the device you'd naturally test from) -- disabling password auth
# would silently lock those out even though the confirming device is fine.
# So this script now audits `journalctl -u sshd --since -30days` per tailnet
# device (names via `tailscale status`, never IPs) before the sshd stage,
# shows it in --dry-run too, and -- if any device still uses a password --
# refuses to proceed past a literal "keys-ready" prompt naming every device
# that needs a key first.
#
# What this does NOT do, on purpose:
#   - By default, nothing to ufw at all. The pre-existing tailscale0 SSH
#     allow rule is never touched by this script, with or without flags.
#   - It never runs `omarchy setup security sshd`. That command's firewall
#     step opens SSH globally rate-limited (not scoped to tailnet/LAN), and
#     its key-enrollment flow is interactive. This script reuses its
#     validation pattern (sshd -t, then sshd -T effective-config check,
#     then reload-not-restart) without its firewall or key steps.
#   - It never widens Docker-published ports. Ports Docker publishes on
#     0.0.0.0 bypass ufw's INPUT chain entirely via the DOCKER-USER chain;
#     if ufw-docker is installed (it is, on hosts that ran Omarchy's
#     firewall install step), that chain already lets RFC1918 (LAN-ish)
#     sources through and blocks everything else. This script only
#     reports what it finds; widening/narrowing that is a separate,
#     explicit decision (see the README in this directory).
#
# Safety:
#   - Audits the last 30 days of sshd logins per tailnet device and refuses
#     to disable password auth (requires typing "keys-ready") until you say
#     every device that still uses a password has a key.
#   - Refuses to disable sshd password auth unless the target user already
#     has at least one key in authorized_keys (never prints its contents).
#   - Validates the sshd drop-in with `sshd -t`, then double-checks with
#     `sshd -T` that the directives actually took effect (an earlier config
#     file can otherwise win), before ever reloading -- and only reloads,
#     never restarts, so an existing session survives a bad config.
#   - The sshd reload is itself covered by a dead-man switch: the previous
#     drop-in state (absent, or whatever it was) is restored and sshd
#     reloaded again automatically after a timeout, unless you confirm a
#     brand-new login from EVERY device the audit found still using a
#     password (not just any one device).
#   - Every ufw rule this script can add carries the comment tag below, so
#     rollback.sh can find and remove exactly those rules and nothing else.
#   - Any ufw change (only reachable via --allow-lan-ssh/--allow-lan-mdns) is
#     covered by its own dead-man switch: a background `sleep N && ufw
#     disable` that only fires if you do not confirm SSH still works (from
#     another tailnet device) before the countdown ends.
#   - Printed ssh commands use this host's Tailscale MagicDNS name (or plain
#     `hostname` as a fallback), detected at runtime -- never hard-coded, so
#     the public script carries no host name of its own.
set -uo pipefail

TAG="dotfiles-ssh-firewall"
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-local-hardening.conf
DEADMAN_SECONDS=300
DRY_RUN=0
ALLOW_LAN_SSH=0
ALLOW_LAN_MDNS=0

LAN_SSH_WHY="not needed today: 0 LAN SSH sessions in 3 weeks (118/118 accepted sessions over that window came from the tailnet, per journalctl -u sshd)"
LAN_MDNS_WHY="not needed today: this host's SSH/firewall hardening doesn't depend on LAN mDNS, and ufw's default-deny already blocks inbound mDNS regardless of this flag -- only add it if you rely on LAN discovery (KDE Connect/LocalSend/Avahi) from this host"

for arg in "$@"; do
  case "$arg" in
  --dry-run) DRY_RUN=1 ;;
  --allow-lan-ssh) ALLOW_LAN_SSH=1 ;;
  --allow-lan-mdns) ALLOW_LAN_MDNS=1 ;;
  -h | --help)
    echo "Usage: $0 [--dry-run] [--allow-lan-ssh] [--allow-lan-mdns]"
    echo
    echo "  --dry-run         Detect current state and print the plan only. No"
    echo "                    sudo needed, nothing is changed."
    echo "  --allow-lan-ssh   Opt in to a rate-limited ufw allow for SSH from"
    echo "                    the LAN CIDR (detected live from 'ip route')."
    echo "                    $LAN_SSH_WHY"
    echo "  --allow-lan-mdns  Opt in to a ufw allow for mDNS (UDP 5353) from"
    echo "                    the LAN CIDR."
    echo "                    $LAN_MDNS_WHY"
    echo
    echo "  With no flags: only the sshd hardening drop-in is offered. No ufw"
    echo "  rule is added or changed."
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
  warn "This applies system changes and needs root. Run with sudo, or pass --dry-run to only inspect."
  exit 1
fi

# --- detect: the non-root user to check authorized_keys for -----------------
TARGET_USER="${TARGET_USER:-${SUDO_USER:-}}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || true)"
fi
TARGET_HOME=""
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
  TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
fi
if [ -z "$TARGET_HOME" ]; then
  TARGET_HOME="$HOME"
fi
AUTHORIZED_KEYS="$TARGET_HOME/.ssh/authorized_keys"

count_keys() {
  [ -s "$AUTHORIZED_KEYS" ] || { echo 0; return; }
  grep -vcE '^[[:space:]]*(#|$)' "$AUTHORIZED_KEYS" 2>/dev/null || echo 0
}

# --- detect: LAN CIDR from the routing table, never hard-coded --------------
detect_lan_cidr() {
  ip -o route show scope link 2>/dev/null | awk '
    $1 ~ /\// {
      dev = "";
      for (i = 1; i <= NF; i++) if ($i == "dev") dev = $(i + 1);
      if (dev !~ /^(lo|docker|br-|veth|tailscale|tun|wg|virbr|vnet)/) { print $1; exit }
    }'
}
LAN_CIDR="$(detect_lan_cidr)"

# --- detect: this host's own name for printed ssh commands -- never hard-coded
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

# --- detect: existing SSH-related ufw rules (file-readable without sudo) ----
# /etc/ufw/user.rules is world-readable; ufw status itself requires root.
existing_ssh_rule_lines() {
  grep -B1 -E 'dport 22\b' /etc/ufw/user.rules /etc/ufw/user6.rules 2>/dev/null | grep '### tuple ###'
}

ufw_service_state() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active ufw.service 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

# --- detect: listening sockets, grouped so the plan is easy to read ---------
print_listener_inventory() {
  if ! command -v ss >/dev/null 2>&1; then
    warn "ss not found; skipping listener inventory."
    return
  fi
  info "Loopback-only (127.0.0.1 / [::1]) -- already unreachable from outside, no rule needed:"
  ss -tulpn 2>/dev/null | awk '$5 ~ /^(127\.0\.0\.1|\[::1\]):/ {print "    " $1, $5}' | sort -u
  info "Bound to all interfaces (0.0.0.0 / [::]) -- reachable unless ufw blocks it:"
  ss -tulpn 2>/dev/null | awk '$5 ~ /^(0\.0\.0\.0|\[::\]):/ {print "    " $1, $5}' | sort -u
  info "Bound to the tailnet address specifically:"
  ss -tulpn 2>/dev/null | awk -v t="$(ip -4 -o addr show tailscale0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)" \
    '$5 ~ ("^"t":") {print "    " $1, $5}'
}

# --- preflight: password vs publickey logins per tailnet device, 30 days ----
# Never prints an IP: sources are mapped to their tailnet device NAME via
# `tailscale status`, and anything that doesn't map to a known device is
# labelled generically instead of printing its address.
declare -A PW_COUNT
declare -A PK_COUNT
declare -A IP_TO_NAME
HAS_PASSWORD_LOGINS=0
PW_DEVICE_LIST=""

build_ip_to_name_map() {
  command -v tailscale >/dev/null 2>&1 || return
  local ip name
  while read -r ip name; do
    [ -n "$ip" ] && [ -n "$name" ] && IP_TO_NAME["$ip"]="$name"
  done < <(tailscale status 2>/dev/null | awk '{print $1, $2}')
}

audit_password_logins() {
  command -v journalctl >/dev/null 2>&1 || return
  build_ip_to_name_map
  local line method ip name
  while IFS= read -r line; do
    if [[ "$line" == *"Accepted password for"* ]]; then
      method=password
    elif [[ "$line" == *"Accepted publickey for"* ]]; then
      method=publickey
    else
      continue
    fi
    ip="$(grep -oE 'from [0-9a-fA-F:.]+' <<<"$line" | awk '{print $2}')"
    [ -z "$ip" ] && continue
    name="${IP_TO_NAME[$ip]:-}"
    if [ -z "$name" ]; then
      if [[ "$ip" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]; then
        name="unknown-tailnet-device"
      else
        name="non-tailnet-source"
      fi
    fi
    if [ "$method" = password ]; then
      PW_COUNT["$name"]=$(( ${PW_COUNT["$name"]:-0} + 1 ))
    else
      PK_COUNT["$name"]=$(( ${PK_COUNT["$name"]:-0} + 1 ))
    fi
  done < <(journalctl -u sshd --since -30days --no-pager 2>/dev/null)
}

print_password_audit() {
  say "Password-login audit (journalctl -u sshd, last 30 days, by device name -- no IPs)"
  audit_password_logins

  local -a names=()
  local k
  for k in "${!PW_COUNT[@]}" "${!PK_COUNT[@]}"; do
    case " ${names[*]-} " in *" $k "*) ;; *) names+=("$k") ;; esac
  done
  if [ "${#names[@]}" -eq 0 ]; then
    info "No accepted SSH logins found in the last 30 days."
    return
  fi

  printf '%-22s %10s %10s\n' "device" "password" "publickey"
  while IFS= read -r k; do
    [ -z "$k" ] && continue
    local pw="${PW_COUNT[$k]:-0}" pk="${PK_COUNT[$k]:-0}"
    if [ "$pw" -gt 0 ]; then
      HAS_PASSWORD_LOGINS=1
      PW_DEVICE_LIST="${PW_DEVICE_LIST:+$PW_DEVICE_LIST, }$k"
      printf '\033[31m%-22s %10s %10s  <- still using a password -- add a key (README "Before you run it")\033[0m\n' "$k" "$pw" "$pk"
    else
      printf '%-22s %10s %10s\n' "$k" "$pw" "$pk"
    fi
  done < <(printf '%s\n' "${names[@]}" | sort)

  if [ "$HAS_PASSWORD_LOGINS" -eq 1 ]; then
    echo
    warn "Password logins in the last 30 days from: $PW_DEVICE_LIST."
    warn "Disabling sshd password auth now would silently lock those out."
    warn "Fix: give each one a key first (README \"Before you run it\"), then re-run."
  fi
}

print_plan() {
  say "Current state"
  info "ufw.service: $(ufw_service_state)"
  info "LAN CIDR detected from 'ip route': ${LAN_CIDR:-<none found>}"
  info "Existing SSH-related ufw rule tuples (interfaces/CIDRs only, no literal host IPs in these):"
  local tuples; tuples="$(existing_ssh_rule_lines | sed -E 's/^.*### tuple ### //' | sed 's/^/    /')"
  if [ -n "$tuples" ]; then printf '%s\n' "$tuples"; else info "    (none found)"; fi
  print_listener_inventory

  print_password_audit

  say "authorized_keys check"
  local n; n="$(count_keys)"
  info "User: $TARGET_USER   File: $AUTHORIZED_KEYS   Key count: $n"
  if [ "$n" -lt 1 ]; then
    warn "No usable key found -- sshd password-auth hardening will be REFUSED."
  fi

  say "Planned changes"
  info "1) ufw (off by default -- opt in per rule):"
  if [ -n "$LAN_CIDR" ]; then
    if [ "$ALLOW_LAN_SSH" -eq 1 ]; then
      info "     ufw limit from $LAN_CIDR to any port 22 proto tcp comment '$TAG-lan-ssh'   [--allow-lan-ssh given]"
    else
      info "     (not applied -- pass --allow-lan-ssh to add) ufw limit from $LAN_CIDR to any port 22 proto tcp"
      info "       $LAN_SSH_WHY"
    fi
    if [ "$ALLOW_LAN_MDNS" -eq 1 ]; then
      info "     ufw allow in from $LAN_CIDR to any port 5353 proto udp comment '$TAG-lan-mdns'   [--allow-lan-mdns given]"
    else
      info "     (not applied -- pass --allow-lan-mdns to add) ufw allow in from $LAN_CIDR to any port 5353 proto udp"
      info "       $LAN_MDNS_WHY"
    fi
  else
    info "     (no LAN interface detected; --allow-lan-* would have nothing to act on)"
  fi
  info "   Always left untouched: the existing tailscale0 SSH allow rule, the"
  info "   LocalSend (53317) rule, the docker-DNS rules, and anything else"
  info "   already in ufw's rule set."
  info "2) sshd drop-in $SSHD_DROPIN (on by default, only if the key check above passed):"
  info "     PasswordAuthentication no"
  info "     KbdInteractiveAuthentication no"
  info "     PermitRootLogin no"
  info "   Validated with 'sshd -t' and 'sshd -T' before any reload; reload"
  info "   (never restart) only if both checks pass. Covered by its own"
  info "   dead-man switch after reload (see below)."
  if [ "$HAS_PASSWORD_LOGINS" -eq 1 ]; then
    info "   Gated on typing 'keys-ready' first -- see the password-login audit above."
  fi
}

print_plan

if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run -- nothing changed."
  exit 0
fi

# --- stage 1: ufw (only touched if an opt-in flag was given) ----------------
if [ "$ALLOW_LAN_SSH" -eq 0 ] && [ "$ALLOW_LAN_MDNS" -eq 0 ]; then
  say "ufw"
  info "No --allow-lan-ssh / --allow-lan-mdns given; leaving ufw exactly as it is."
elif [ -z "$LAN_CIDR" ]; then
  warn "No LAN CIDR detected; --allow-lan-* has nothing to act on, skipping ufw."
else
  echo
  read -r -p "Apply the opted-in ufw change(s) above? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    info "Skipping ufw changes."
  else
    say "Applying ufw changes"
    if [ "$ALLOW_LAN_SSH" -eq 1 ]; then
      if ! ufw status 2>/dev/null | grep -q "$TAG-lan-ssh"; then
        ufw limit from "$LAN_CIDR" to any port 22 proto tcp comment "$TAG-lan-ssh"
      else
        info "LAN SSH rule already present, skipping."
      fi
    fi
    if [ "$ALLOW_LAN_MDNS" -eq 1 ]; then
      if ! ufw status 2>/dev/null | grep -q "$TAG-lan-mdns"; then
        ufw allow in from "$LAN_CIDR" to any port 5353 proto udp comment "$TAG-lan-mdns"
      else
        info "LAN mDNS rule already present, skipping."
      fi
    fi
    ufw reload

    say "ufw dead-man switch armed"
    info "A background job will run: sleep $DEADMAN_SECONDS && ufw disable"
    info "If sshd is somehow unreachable now, that fully reopens the firewall"
    info "after ${DEADMAN_SECONDS}s so you are never locked out by this script."
    info
    info "From another tailnet device, confirm SSH still works:"
    info "    ssh $TARGET_USER@$SSH_TARGET"
    info
    ( sleep "$DEADMAN_SECONDS" && warn "No confirmation received in time -- disabling ufw for safety." && ufw disable ) &
    deadman_pid=$!
    read -r -p "Once that ssh test above succeeds, press Enter to cancel the safety rollback (Ctrl-C also cancels nothing -- it just leaves the timer running): " _
    if kill "$deadman_pid" 2>/dev/null; then
      info "Safety rollback cancelled. ufw rules stay as applied."
    else
      warn "Safety rollback already fired (or wasn't running); check 'ufw status'."
    fi
  fi
fi

# --- preflight gate: password-login audit must be acknowledged -------------
# The dead-man switch below only proves SSH works from whichever device you
# confirm from. If other devices have only ever used a password here,
# disabling password auth would lock those out even if the confirming
# device is fine. Require an explicit, specific acknowledgement instead of
# a plain y/N.
if [ "$HAS_PASSWORD_LOGINS" -eq 1 ]; then
  echo
  warn "Password logins in the last 30 days from: $PW_DEVICE_LIST."
  warn "Disabling sshd password auth now would lock those devices out until"
  warn "they each have a key (README \"Before you run it\")."
  read -r -p "Type exactly 'keys-ready' once every device listed above has a working key, or anything else to stop here: " keys_confirm
  if [ "$keys_confirm" != "keys-ready" ]; then
    warn "Not confirmed. Leaving sshd password auth enabled; nothing else changed."
    exit 1
  fi
fi

# --- stage 2: sshd hardening drop-in (on by default) ------------------------
echo
read -r -p "Apply the sshd hardening drop-in above? [y/N] " ans2
if [[ ! "$ans2" =~ ^[Yy]$ ]]; then
  info "Skipping sshd hardening."
  exit 0
fi

say "Applying sshd hardening"
n="$(count_keys)"
if [ "$n" -lt 1 ]; then
  warn "Refusing: $AUTHORIZED_KEYS has no usable key. Add one first (e.g. via"
  warn "'omarchy-setup-security-sshd --key=...' or by hand), then re-run."
  exit 1
fi

# Snapshot whatever was there before, so a failed validation or an unconfirmed
# dead-man timeout can restore it exactly rather than just deleting it.
HAD_DROPIN=0
PREV_DROPIN_BACKUP=""
if [ -f "$SSHD_DROPIN" ]; then
  HAD_DROPIN=1
  PREV_DROPIN_BACKUP="$(mktemp /tmp/sshd-local-hardening-prev.XXXXXX)"
  cp -a "$SSHD_DROPIN" "$PREV_DROPIN_BACKUP"
fi

restore_previous_dropin() {
  if [ "$HAD_DROPIN" -eq 1 ] && [ -n "$PREV_DROPIN_BACKUP" ] && [ -f "$PREV_DROPIN_BACKUP" ]; then
    cp -a "$PREV_DROPIN_BACKUP" "$SSHD_DROPIN"
  else
    rm -f "$SSHD_DROPIN"
  fi
}

cleanup_backup() {
  [ -n "$PREV_DROPIN_BACKUP" ] && rm -f "$PREV_DROPIN_BACKUP"
}

install -Dm644 /dev/stdin "$SSHD_DROPIN" <<'CONF'
# Written by dotfiles/system/ssh-firewall/apply.sh.
# Delete this file and `systemctl reload sshd` to restore the previous
# authentication settings (or run rollback.sh in this directory).
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
CONF

if ! sshd -t; then
  warn "sshd rejected the new config; restoring the previous state."
  restore_previous_dropin
  cleanup_backup
  exit 1
fi

effective="$(sshd -T 2>/dev/null || true)"
ok=1
for directive in "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin no"; do
  if ! grep -qixF "$directive" <<<"$effective"; then
    warn "Directive did not take effect: $directive (an earlier sshd_config file may win for it)."
    ok=0
  fi
done
if [ "$ok" -ne 1 ]; then
  warn "Effective config check failed; restoring the previous state."
  restore_previous_dropin
  cleanup_backup
  exit 1
fi

systemctl reload sshd.service

say "sshd dead-man switch armed"
info "A background job will restore the previous sshd auth config (${HAD_DROPIN:+and reload sshd }) after ${DEADMAN_SECONDS}s"
if [ -n "$PW_DEVICE_LIST" ]; then
  info "unless you confirm a FRESH login (a new session, not a reused one) works from"
  info "EACH of these devices that used a password in the last 30 days: $PW_DEVICE_LIST."
  info "Testing from just one of them is not enough."
else
  info "unless you confirm a FRESH tailnet login works (don't reuse an already-open session)."
fi
info
info "From each of those devices in turn, open a new session:"
info "    ssh $TARGET_USER@$SSH_TARGET"
info
(
  sleep "$DEADMAN_SECONDS"
  warn "No confirmation received in time -- restoring the previous sshd auth config."
  restore_previous_dropin
  if sshd -t; then
    systemctl reload sshd.service
  else
    warn "Restored config also failed sshd -t; manual attention needed at $SSHD_DROPIN."
  fi
  cleanup_backup
) &
sshd_deadman_pid=$!
read -r -p "Once EVERY device above has a confirmed fresh login, press Enter to cancel the safety rollback: " _
if kill "$sshd_deadman_pid" 2>/dev/null; then
  info "Safety rollback cancelled. sshd hardening stays applied."
  cleanup_backup
else
  warn "Safety rollback already fired (or wasn't running); check sshd auth settings."
fi

say "Done"
info "sshd now rejects passwords and root logins; key-only auth for $TARGET_USER."
if [ -n "$PW_DEVICE_LIST" ]; then
  info "Confirmed fresh logins were required from: $PW_DEVICE_LIST."
fi
info "Test any time: ssh $TARGET_USER@$SSH_TARGET"
info "To undo everything this script did: system/ssh-firewall/rollback.sh"
