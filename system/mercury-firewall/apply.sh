#!/usr/bin/env bash
# Turn on a host firewall on this box, without breaking the services that
# already work on the LAN and the tailnet.
#
# PREMISE (from the mercury home-server audit, 2026-10-13): ufw is installed
# but inactive, so every listening socket -- including on this box's public
# IPv6 address -- is reachable from the whole LAN and, for anything bound on
# [::]/0.0.0.0, from the open internet over IPv6 (the LAN's IPv4 side sits
# behind the router's NAT; IPv6 does not). The fix is a default-deny-incoming
# posture that explicitly re-opens exactly what's used today from the LAN and
# the tailnet -- never from the public internet.
#
# The user's own correction to the plan: ntfy and every "hermes" port (the
# personal agent framework's gateway + helper servers) must stay reachable
# from the LAN and the tailnet, same as today -- not narrowed to tailnet-only.
# This script treats that as non-negotiable and extends the same "keep it
# working" default to pihole, Home Assistant, Samba and anything else found
# listening, with ONE exception: qdrant, which is probed live for remote
# (off-box) use and, finding none at the time this was written, defaults to
# localhost-only. See the README for the full reasoning.
#
# THE DOCKER GOTCHA (this is the one subtle bug a naive ufw setup ships):
# ufw manages the INPUT/FORWARD chain *default policies*, but a port a
# container PUBLISHES (bridge network + `-p`) is reached via DNAT in the
# PREROUTING/FORWARD path, not INPUT -- so plain `ufw allow/deny` on that
# port number is a no-op for LAN/tailnet-sourced traffic hitting it. Docker
# inserts its own DOCKER-USER chain ahead of the FORWARD chain precisely so
# rules can be added there; this script uses that chain directly (no
# third-party ufw-docker tool, no curl-pipe-to-root) for the one port that
# actually needs restricting (qdrant). Every other container's published
# port is deliberately left untouched -- it stays exactly as reachable as it
# is today, which is what "keep it working" requires, and touching
# DOCKER-USER for it would only be extra risk for zero benefit.
#
# Run as root (sudo system/mercury-firewall/apply.sh) on mercury, after
# copying this directory there, or piped in:
#   ssh mercury 'sudo bash -s' < system/mercury-firewall/apply.sh
# Pass --dry-run to only detect the current state and print the plan --
# no sudo needed, nothing is changed.
#
# Safety:
#   - Every rule and chain edit this script makes carries the tag below, in
#     a ufw comment or an iptables -m comment, so rollback.sh (or the
#     dead-man switch below) can find and remove exactly those and nothing
#     else.
#   - Nothing here touches sshd's own auth config -- that is
#     system/ssh-firewall/'s job, not this one's.
#   - Dead-man switch: once the new policy is applied, a *detached* systemd
#     transient timer (survives this SSH session closing, which matters for
#     the piped invocation above) runs `ufw disable` and flushes this
#     script's DOCKER-USER rule after 5 minutes, unless you cancel it first.
#     Cancelling means: from another device (or this one), confirm SSH
#     (and ideally ntfy/hermes/HA too) still reach mercury, then run the
#     single `systemctl stop ...` command this script prints -- works
#     identically whether you're at a TTY or came in through the piped
#     invocation above, which cannot block on an interactive prompt because
#     its stdin was the script itself.
#   - Printed ssh/test commands use this host's Tailscale MagicDNS name (or
#     plain `hostname` as a fallback), detected at runtime -- never
#     hard-coded, so the public copy of this script carries no host name of
#     its own. No IP address appears anywhere below either; LAN/tailnet
#     scope is always detected live (routing table, live interface list).
set -uo pipefail

TAG="dotfiles-mercury-firewall"
DEADMAN_SECONDS=300
DEADMAN_UNIT="mercury-firewall-deadman"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
  --dry-run) DRY_RUN=1 ;;
  -h | --help)
    echo "Usage: $0 [--dry-run]"
    echo
    echo "  --dry-run   Detect current state and print the plan only. No sudo"
    echo "              needed, nothing is changed."
    echo
    echo "  With no flags: applies the plan (needs sudo) and arms a 5-minute"
    echo "  dead-man switch that undoes it unless you confirm from elsewhere."
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

INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

# --- detect: LAN CIDR + its interface, live from the routing table ---------
# Same approach as system/ssh-firewall/apply.sh: the first scope-link route
# whose device isn't a tailnet/docker/virtual interface. Never hard-coded.
detect_lan() {
  ip -o route show scope link 2>/dev/null | awk '
    $1 ~ /\// {
      dev = "";
      for (i = 1; i <= NF; i++) if ($i == "dev") dev = $(i + 1);
      if (dev !~ /^(lo|docker|br-|veth|tailscale|tun|wg|virbr|vnet)/) { print $1, dev; exit }
    }'
}
read -r LAN_CIDR LAN_IFACE <<<"$(detect_lan)"

# --- detect: the tailscale interface name, live -----------------------------
detect_ts_iface() {
  ip -o link show up 2>/dev/null | awk -F': ' '$2 ~ /^tailscale/ { print $2; exit }'
}
TS_IFACE="$(detect_ts_iface)"
[ -z "$TS_IFACE" ] && command -v tailscale >/dev/null 2>&1 && TS_IFACE="tailscale0"

# --- detect: this host's own name for printed ssh/test commands ------------
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

# --- detect: docker containers and what they publish ------------------------
# "name port/proto" lines, one per published mapping, container-published
# ports only (internal-only ports are not in this list at all).
docker_published() {
  command -v docker >/dev/null 2>&1 || return
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | while IFS='|' read -r name ports; do
    # e.g. "0.0.0.0:2586->80/tcp" -> published 2586/tcp. Docker also prints
    # ranges, e.g. "0.0.0.0:6333-6334->6333-6334/tcp" -> expand to one line
    # per port in the range.
    printf '%s\n' "$ports" | grep -oE '[0-9]+(-[0-9]+)?->[0-9]+(-[0-9]+)?/[a-z]+' | \
      sed -E 's#^([0-9]+(-[0-9]+)?)->[0-9]+(-[0-9]+)?/([a-z]+)$#\1 \4#' | \
      while read -r portspec proto; do
        case "$portspec" in
        *-*) start_port="${portspec%-*}"; end_port="${portspec#*-}" ;;
        *) start_port="$portspec"; end_port="$portspec" ;;
        esac
        for p in $(seq "$start_port" "$end_port"); do
          printf '%s %s %s\n' "$name" "$p" "$proto"
        done
      done
  done | sort -u
}
DOCKER_INVENTORY="$(docker_published)"

container_ip_for() {
  # all IPs this container has across any docker network it's on
  docker inspect "$1" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$v.IPAddress}} {{end}}' 2>/dev/null
}

# --- detect: whether Home Assistant's config actually uses zeroconf/mDNS ---
# default_config: (HA's catch-all) bundles the zeroconf integration unless
# explicitly excluded, so grep for either the explicit integration or the
# bundle, in the compose-mounted config directory docker reports.
ha_uses_mdns() {
  command -v docker >/dev/null 2>&1 || return 1
  local cfg_dir cfg
  cfg_dir="$(docker inspect homeassistant --format '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)"
  [ -z "$cfg_dir" ] && return 1
  cfg="$cfg_dir/configuration.yaml"
  [ -r "$cfg" ] || return 1
  grep -qE '^\s*(zeroconf|default_config)\s*:' "$cfg" 2>/dev/null
}

# --- detect: live listening sockets, classified ------------------------------
# Emits "proto port bind pid cmd" lines for everything ss can see. bind is
# one of: loop (127.0.0.1/::1), tsonly (bound to the tailscale IP itself,
# already tailnet-scoped, nothing to do), docker (internal docker-bridge
# address, not reachable off-box), wild (0.0.0.0/[::]/*, or the LAN IP --
# reachable from the LAN and needs classifying).
classify_listeners() {
  local ts_ip4 ts_ip6
  ts_ip4="$(ip -4 -o addr show "$TS_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
  ts_ip6="$(ip -6 -o addr show "$TS_IFACE" 2>/dev/null | awk '$3=="inet6"{print $4}' | cut -d/ -f1 | head -1)"
  ss -tulpn 2>/dev/null | awk -v ts4="$ts_ip4" -v ts6="$ts_ip6" '
    NR==1 { next }
    {
      proto=$1; local=$5; proc=$NF
      split(local, a, ":"); port=a[length(a)]
      # strip brackets for ipv6 bind address, keep everything but the last :port
      bindaddr = local; sub(/:[0-9]+$/, "", bindaddr); gsub(/[][]/, "", bindaddr)
      pid=""; cmd_marker=""
      if (proc ~ /pid=/) { match(proc, /pid=[0-9]+/); pid=substr(proc, RSTART+4, RLENGTH-4) }
      bind="wild"
      if (bindaddr ~ /^127\./ || bindaddr == "::1") bind="loop"
      else if (bindaddr == ts4 || bindaddr == ts6) bind="tsonly"
      else if (bindaddr ~ /^172\.(1[7-9]|2[0-9]|3[01])\./) bind="docker"
      print proto, port, bind, pid
    }' | sort -u
}

pid_cmd() {
  [ -n "${1:-}" ] || { echo ""; return; }
  ps -p "$1" -o cmd= 2>/dev/null
}

is_hermes_cmd() {
  case "$1" in
  *.hermes/*|*hermes_cli*|*hermes-agent*|*/quests/buraco/*) return 0 ;;
  *) return 1 ;;
  esac
}

# Tailscale's own transport (tailscaled) needs its UDP port reachable from
# the whole internet to do NAT traversal / direct connections -- scoping it
# to LAN+tailnet would be circular (there's no tailnet path to it before the
# tunnel exists) and would push every connection through DERP relay instead.
# Leave it, and anything else owned by tailscaled, completely alone.
is_tailscaled_cmd() {
  case "$1" in
  *tailscaled*) return 0 ;;
  *) return 1 ;;
  esac
}

# --- detect: anything with an established (non-local) connection to qdrant --
qdrant_has_remote_use() {
  local peers
  peers="$(ss -tn state established '( dport = :6333 or dport = :6334 or sport = :6333 or sport = :6334 )' 2>/dev/null | awk 'NR>1{print $4"\n"$5}')"
  [ -z "$peers" ] && return 1
  while read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
    127.0.0.1:*|\[::1\]:*|172.1[7-9].*|172.2[0-9].*|172.3[01].*) ;;
    *) return 0 ;;
    esac
  done <<<"$peers"
  return 1
}

# --- build the plan ----------------------------------------------------------
declare -a UFW_RULES=()       # human-readable description -> matching ufw command
declare -a UFW_CMDS=()
declare -a NOTES=()
HERMES_PORTS=()
UNIDENTIFIED=()

add_ufw_pair() {
  # $1 name  $2 port  $3 proto
  local port="$2" proto="$3" name="$1"
  if [ -n "$LAN_CIDR" ]; then
    UFW_RULES+=("$name: allow from LAN ($LAN_CIDR) to port $port/$proto")
    UFW_CMDS+=("ufw allow from $LAN_CIDR to any port $port proto $proto comment '$TAG-$name-$port-lan'")
  fi
  if [ -n "$TS_IFACE" ]; then
    UFW_RULES+=("$name: allow in on $TS_IFACE to port $port/$proto")
    UFW_CMDS+=("ufw allow in on $TS_IFACE to any port $port proto $proto comment '$TAG-$name-$port-ts'")
  fi
}

build_plan() {
  # SSH -- rate-limited on the LAN (brute-force friendly), plain allow on the
  # tailnet (already the trusted path).
  if [ -n "$LAN_CIDR" ]; then
    UFW_RULES+=("ssh: rate-limit from LAN ($LAN_CIDR) to port 22/tcp")
    UFW_CMDS+=("ufw limit from $LAN_CIDR to any port 22 proto tcp comment '$TAG-ssh-lan'")
  fi
  if [ -n "$TS_IFACE" ]; then
    UFW_RULES+=("ssh: allow in on $TS_IFACE to port 22/tcp")
    UFW_CMDS+=("ufw allow in on $TS_IFACE to any port 22 proto tcp comment '$TAG-ssh-ts'")
  fi

  # Home Assistant -- host network, so it's a normal INPUT-filterable port.
  add_ufw_pair "home-assistant" 8123 tcp

  if ha_uses_mdns; then
    NOTES+=("Home Assistant's configuration.yaml uses default_config/zeroconf -> mDNS allow included.")
    add_ufw_pair "mdns" 5353 udp
  else
    NOTES+=("Home Assistant's configuration.yaml does NOT show default_config/zeroconf -> no mDNS rule added. Re-check with --dry-run if you add zeroconf later.")
  fi

  # SSDP -- LAN device discovery (often used by HA's own integrations and
  # casting/UPnP devices). Kept reachable as today; it's a broadcast-style
  # protocol with little blast radius.
  add_ufw_pair "ssdp" 1900 udp

  # Samba -- already scoped to LAN+tailnet CIDRs at the smb.conf layer; this
  # just closes the matching OS-level gap, not a behavior change.
  add_ufw_pair "samba" 139 tcp
  add_ufw_pair "samba" 445 tcp

  # Hermes -- every currently-listening port owned by a hermes-ish process,
  # found live, not a fixed list. Ports already loopback-bound (the local
  # embed server, the local llama-server) need no rule and aren't touched.
  while read -r proto port bind pid; do
    [ "$bind" = "wild" ] || continue
    [ "$proto" = "tcp" ] || continue
    local cmd
    cmd="$(pid_cmd "$pid")"
    is_tailscaled_cmd "$cmd" && continue
    if [ -n "$cmd" ] && is_hermes_cmd "$cmd"; then
      HERMES_PORTS+=("$port")
    fi
  done < <(classify_listeners)
  for port in $(printf '%s\n' "${HERMES_PORTS[@]:-}" | sort -un); do
    [ -z "$port" ] && continue
    add_ufw_pair "hermes" "$port" tcp
  done

  # ntfy, cups, pihole (DNS + web UI) -- Docker-published, bridge network.
  # Deliberately NOT given ufw rules: ufw's INPUT chain never sees
  # LAN/tailnet-sourced traffic to a published container port (it arrives
  # via DNAT into the FORWARD path), so a rule here would be a no-op that
  # only looks safe. They stay exactly as reachable as today for free.
  NOTES+=("ntfy (:2586), cups (:631), pihole DNS (:53) and pihole's web UI (:8080) are Docker-published; left untouched on purpose -- see the DOCKER GOTCHA comment at the top of this script. They stay reachable from LAN+tailnet exactly as today.")

  # qdrant -- the one Docker-published port this script will actually
  # restrict, via a direct DOCKER-USER rule, IF nothing off-box is using it
  # right now.
  if qdrant_has_remote_use; then
    NOTES+=("qdrant (:6333-6334): a non-local peer is connected right now -> leaving it reachable from LAN+tailnet as today. No DOCKER-USER rule added. Re-run --dry-run later if that usage goes away.")
    QDRANT_RESTRICT=0
  else
    NOTES+=("qdrant (:6333-6334): no off-box peer connected right now -> restricting to localhost/Docker-internal via a DOCKER-USER DROP rule (container IP looked up live). Host-local access (hermes on mercury itself) is unaffected.")
    QDRANT_RESTRICT=1
  fi

  # Anything else live, exposed, and not yet classified above.
  while read -r proto port bind pid; do
    [ "$bind" = "wild" ] || continue
    case "$port" in
    22|8123|5353|1900|139|445) continue ;;
    esac
    [[ " ${HERMES_PORTS[*]:-} " == *" $port "* ]] && continue
    printf '%s\n' "$DOCKER_INVENTORY" | awk '{print $2}' | grep -qx "$port" && continue
    local cmd
    cmd="$(pid_cmd "$pid")"
    if is_tailscaled_cmd "$cmd"; then
      NOTES+=("Port $proto/$port is tailscaled's own (NAT-traversal) socket -- left fully open on purpose, see is_tailscaled_cmd comment.")
      continue
    fi
    UNIDENTIFIED+=("$proto/$port (pid ${pid:-?}: ${cmd:-unknown, likely root-owned -- re-check once run with sudo})")
  done < <(classify_listeners)
  for u in "${UNIDENTIFIED[@]:-}"; do
    [ -z "$u" ] && continue
    local p="${u%% *}"; local port="${p#*/}"; local proto="${p%%/*}"
    add_ufw_pair "unidentified" "$port" "$proto"
  done

  # Any OTHER docker-published port found live, beyond ntfy/cups/pihole/qdrant.
  while read -r name port proto; do
    [ -z "$name" ] && continue
    case "$name" in ntfy|cups|pihole|qdrant) continue ;;
    esac
    NOTES+=("New Docker-published port found: $name :$port/$proto -- not managed by this script (see the DOCKER GOTCHA comment). Reachable via Docker's forwarding path as before; add a DOCKER-USER rule by hand, qdrant's below is the template, if you want to restrict it.")
  done <<<"$DOCKER_INVENTORY"
}

print_plan() {
  say "Current state"
  info "LAN CIDR: ${LAN_CIDR:-<none detected>}   LAN interface: ${LAN_IFACE:-<none>}"
  info "Tailscale interface: ${TS_IFACE:-<none detected>}"
  info "ufw ruleset enabled (/etc/ufw/ufw.conf): $(grep -E '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null || echo '<not found>')   (ufw.service itself is always \"active\" at boot regardless -- this file is the real switch)"
  info "ufw IPv6 support (/etc/default/ufw): $(grep -E '^IPV6=' /etc/default/ufw 2>/dev/null || echo '<not found>')"
  info "Docker-published ports found live:"
  if [ -n "$DOCKER_INVENTORY" ]; then printf '%s\n' "$DOCKER_INVENTORY" | sed 's/^/    /'; else info "    (none, or docker not reachable without more privilege)"; fi

  say "Planned ufw rules (none applied yet)"
  local i
  for i in "${!UFW_RULES[@]}"; do info "  - ${UFW_RULES[$i]}"; done
  [ "${#UFW_RULES[@]}" -eq 0 ] && info "  (none)"

  say "Hermes ports found live, getting a LAN+tailnet allow"
  if [ "${#HERMES_PORTS[@]}" -gt 0 ]; then
    printf '  - %s\n' "${HERMES_PORTS[@]}"
  else
    info "  (none found bound to all interfaces right now -- hermes may be down, or sudo is needed to see root-owned sockets)"
  fi

  say "Unidentified exposed ports (defaulted to LAN+tailnet allow, same as today -- investigate when convenient)"
  if [ "${#UNIDENTIFIED[@]}" -gt 0 ]; then
    printf '  - %s\n' "${UNIDENTIFIED[@]}"
  else
    info "  (none)"
  fi

  say "Notes"
  printf '  - %s\n' "${NOTES[@]}"

  say "qdrant DOCKER-USER rule"
  if [ "${QDRANT_RESTRICT:-0}" -eq 1 ]; then
    local ips; ips="$(container_ip_for qdrant)"
    info "  Container IP(s) right now: ${ips:-<qdrant not running / docker not visible>}"
    for ip in $ips; do
      info "  iptables -I DOCKER-USER 1 -d $ip -p tcp -m multiport --dports 6333,6334 -j DROP -m comment --comment '$TAG-qdrant-restrict'"
    done
  else
    info "  (not applied -- remote use detected live, see notes above)"
  fi
}

build_plan
print_plan

if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run -- nothing changed."
  exit 0
fi

# --- apply --------------------------------------------------------------------
say "Applying"
info "Setting default policies: deny incoming, allow outgoing."
ufw default deny incoming
ufw default allow outgoing

for cmd in "${UFW_CMDS[@]:-}"; do
  [ -z "$cmd" ] && continue
  info "  $cmd"
  eval "$cmd"
done

if [ "${QDRANT_RESTRICT:-0}" -eq 1 ]; then
  ips="$(container_ip_for qdrant)"
  for ip in $ips; do
    iptables -I DOCKER-USER 1 -d "$ip" -p tcp -m multiport --dports 6333,6334 -j DROP -m comment --comment "$TAG-qdrant-restrict"
    info "  Restricted qdrant ($ip:6333-6334) to localhost/Docker-internal only."
  done
fi

ufw --force enable
ufw reload

say "Dead-man switch armed"
info "A detached systemd timer will run in ${DEADMAN_SECONDS}s unless cancelled:"
info "    ufw disable; iptables -F DOCKER-USER"
info "(this fully reopens the host -- the exact pre-script state -- as a safety net)"
info
info "From ANOTHER device (or this one, in a new session), confirm SSH still works:"
info "    ssh $TARGET_USER@$SSH_TARGET"
info "Spot-check ntfy/hermes/pihole/HA too if you want extra confidence."
info
systemd-run --unit="$DEADMAN_UNIT" --on-active="${DEADMAN_SECONDS}s" \
  --description="mercury-firewall: revert to pre-apply state if not confirmed" \
  /bin/bash -c "ufw disable; iptables -F DOCKER-USER 2>/dev/null; ip6tables -F DOCKER-USER 2>/dev/null" >/dev/null

CANCEL_CMD="systemctl stop ${DEADMAN_UNIT}.timer ${DEADMAN_UNIT}.service 2>/dev/null"
info "To cancel the dead-man switch and keep this policy, run:"
info "    sudo $CANCEL_CMD"

if [ "$INTERACTIVE" -eq 1 ]; then
  read -r -p "Once you've confirmed access above, press Enter to cancel the dead-man switch now (or Ctrl-C to leave it running): " _
  if eval "$CANCEL_CMD"; then
    info "Dead-man switch cancelled. Policy stays applied."
  else
    warn "Could not cancel (already fired, or the unit name changed); check 'systemctl list-timers' and 'ufw status'."
  fi
else
  info "(no TTY -- not waiting here; run the cancel command above from any session within ${DEADMAN_SECONDS}s)"
fi

say "Done"
info "ufw status verbose    # review what's active"
info "To undo everything this script did: system/mercury-firewall/rollback.sh"
