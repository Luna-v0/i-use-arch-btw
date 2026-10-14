# mercury-firewall

Turns on a host firewall on mercury (ufw default-deny-incoming) without
breaking anything that works today from the LAN or the tailnet. Not stowed;
copy this directory to mercury and run `apply.sh` by hand with `sudo`, or
pipe it in over SSH (see below).

## Why

Mercury has `ufw` installed but inactive (`ENABLED=no`), so every listening
socket is reachable from the whole home LAN -- and anything bound to
`0.0.0.0`/`[::]` is also reachable from the open internet over mercury's
public IPv6 address, since IPv6 isn't NATed by the home router the way IPv4
is. That's the one real gap: see
`_global/reports/2026-10-13-mercury-home-server.md` in the maintenance repo
for the full audit this is based on.

The user's correction to the obvious "lock it all down to tailnet-only"
plan: ntfy and every "hermes" port (the personal agent framework) must stay
reachable from the LAN too, same as today. This script generalizes that:
**everything found listening today stays reachable from the LAN and the
tailnet; nothing becomes reachable from the public internet.** The one
exception is `qdrant`, which gets probed live for any off-box use and
defaults to localhost-only if none is found (see "qdrant" below) --
everything else, including things this script doesn't specifically name
(cups, the two mystery ports behind Home Assistant's camera streaming,
anything added later), defaults to "keep it reachable as today" rather than
silently dropping it.

## The Docker gotcha

A port a container **publishes** (`-p 2586:80`, bridge networking) is
reached through Docker's own DNAT rules in the `FORWARD` path, not through
`INPUT` -- so a plain `ufw allow`/`ufw deny` on that port number does
nothing for LAN- or tailnet-sourced traffic hitting it; ufw's own docs call
this out. Docker inserts a `DOCKER-USER` chain specifically so you can add
rules that actually see that traffic.

This script does **not** install the third-party `ufw-docker` helper (no
curl-pipe-to-root, nothing pulled from the internet at apply time). It
writes directly into `DOCKER-USER`, and only for the one port that's
actually meant to change: qdrant. ntfy, cups and pihole's two
Docker-published ports are deliberately left untouched -- they stay exactly
as reachable as they are today, which is the whole point, and touching
`DOCKER-USER` for them would just be extra risk for no benefit.

Home Assistant runs with `--network host`, so its ports (8123, and the two
`go2rtc` camera-streaming ports it opens) are normal host-bound sockets --
`ufw` handles them the ordinary way.

## What it does

`apply.sh` (no args) does this, after printing the plan and waiting for
`sudo`:

1. **Inventories live**, via `ss -tulpn` plus `docker ps`: every listening
   socket, mapped to a service where possible (by known port, by container
   name for Docker-published ports, or by matching a hermes-ish process
   path for the helper servers -- not a fixed port list, so a new hermes
   server picks up a rule automatically next time this is run).
2. Sets **`ufw default deny incoming`, `ufw default allow outgoing`**.
3. Allows **SSH** (rate-limited from the LAN, plain-allowed on the tailnet
   interface), **every hermes port found live**, **Home Assistant** (8123 +
   mDNS, since its `configuration.yaml` uses `default_config` which bundles
   zeroconf -- checked live, not assumed), **SSDP** (1900/udp, LAN
   discovery) and **Samba** (139, 445 -- matches `smb.conf`'s own existing
   LAN+tailnet scope, just closes the OS-level gap to match it) from the LAN
   CIDR (detected live from the routing table) and in on the tailscale
   interface (detected live).
4. Leaves **ntfy, cups, pihole's DNS (53) and web UI (8080)** completely
   alone -- see "The Docker gotcha" above. They stay reachable exactly as
   today for free.
5. **qdrant**: checks `ss -tn` for any established connection from a peer
   that isn't localhost or a Docker-internal address, right now. None found
   -> inserts one `DOCKER-USER` rule (container IP looked up live) dropping
   forwarded traffic to 6333/6334, i.e. localhost/Docker-internal only.
   Remote use found -> leaves it reachable from LAN+tailnet like everything
   else, and says so.
6. Anything else found listening and exposed, not matched above, defaults
   to the same LAN+tailnet allow as everything else -- flagged loudly in the
   plan as "unidentified" so you know to look at it, but not silently
   dropped. Tailscale's own transport port is explicitly excluded from this
   (see the comment on `is_tailscaled_cmd` in apply.sh) -- scoping it to
   LAN+tailnet would be circular and would push every tailnet connection
   through DERP relay instead of direct.
7. Arms a **dead-man switch**: a detached `systemd-run` timer (survives the
   SSH session closing -- see "Piped invocation" below) that runs
   `ufw disable; iptables -F DOCKER-USER` after 5 minutes unless cancelled.

## Before you run it for real

Run `apply.sh --dry-run` first (no sudo needed) and read the plan,
especially:

- **"Unidentified exposed ports"** -- on mercury today this includes two
  ports behind Home Assistant's `go2rtc` camera-streaming add-on (confirmed
  via `docker logs homeassistant`, bundled with HA's own container), a CUPS
  secondary listener (confirmed via its response headers,
  `Server: CUPS/2.4`), and a plain Python `uvicorn` service on port 80
  (unconfirmed which one -- likely another hermes-ish helper that needs a
  privileged port, since its PID is root-owned and hidden without `sudo`;
  resolve this by running `sudo ss -tulpn | grep :80` once, or just note
  that `--dry-run` with `sudo` will classify it properly). All of these
  default to staying reachable from LAN+tailnet, so nothing breaks either
  way -- this is purely about knowing what's on the box.
- **"qdrant DOCKER-USER rule"** -- confirms whether it found remote use. At
  the time this was written, no established connection came from off-box,
  so the default is localhost-only. If you use qdrant from another machine for
  anything, check this line before running for real.
- The **Docker-published ports list** -- make sure it matches what you
  expect to still be reachable (ntfy, cups, pihole x2, qdrant).

## Run

```sh
# detect + print the plan, no sudo, no changes:
./system/mercury-firewall/apply.sh --dry-run

# apply for real, from a shell on mercury:
sudo ./system/mercury-firewall/apply.sh
```

### Piped invocation

```sh
ssh mercury 'sudo bash -s' < system/mercury-firewall/apply.sh
```

This has no TTY, so the script can't block on an interactive "press Enter to
confirm" prompt -- it detects that (`[ -t 0 ]`) and just applies the plan,
arms the dead-man switch, and prints the cancel command, then returns. From
**any** session (the same one, a new SSH login, another device), within 5
minutes, run the command it printed:

```sh
sudo systemctl stop mercury-firewall-deadman.timer mercury-firewall-deadman.service
```

If you don't, the dead-man timer fires on its own: `ufw disable` plus
flushing the `DOCKER-USER` chain, which fully reopens the host -- the exact
pre-apply state -- so a bad rule can't lock you out.

## Rollback

```sh
./system/mercury-firewall/rollback.sh --dry-run
sudo ./system/mercury-firewall/rollback.sh
```

Removes every ufw rule tagged `dotfiles-mercury-firewall-*` and the qdrant
`DOCKER-USER` rule, then asks whether to also `ufw disable` (mercury's state
before `apply.sh` ever ran). sshd is never touched by either script --
that's `system/ssh-firewall/`'s job.

## What this script does NOT do

- Touch sshd's auth config. That's `system/ssh-firewall/` in this same
  directory.
- Install `ufw-docker` or any other third-party tool. The one
  `DOCKER-USER` rule it needs (for qdrant) is written directly.
- Hard-code mercury's hostname, LAN IP, or tailnet IP anywhere -- this repo
  is public. LAN CIDR and the tailscale interface are detected live every
  run; the printed SSH command uses `tailscale status --json`'s
  `Self.DNSName`, falling back to plain `hostname`.
- Guess at what a new, as-yet-unseen Docker-published port should do --
  anything beyond ntfy/cups/pihole/qdrant found live is flagged in the plan
  with a note pointing at the qdrant rule as the template, not silently
  firewalled off.
