# ssh-firewall

Turns off sshd password/root auth, without risking a lockout. Not stowed;
you run these scripts by hand with `sudo`.

## Corrected premise (two rounds)

1. This host's ufw is already active, default-deny-incoming, and already
   has a tailscale0-only SSH allow rule. 3 weeks of `journalctl -u sshd`
   show 118/118 accepted sessions came from the tailnet; zero from the LAN.
   So by default `apply.sh` changes **no ufw rule** — adding a LAN-scoped
   SSH/mDNS allow would only loosen an already-correct posture for access
   nobody uses. Those two LAN rules still exist in the script, but only
   behind explicit opt-in flags; see below.
2. A plain "SSH still works from one device" check isn't enough: 30 days of
   `journalctl -u sshd` show real password logins from devices that have
   **never** used a key here — your phone and a second laptop — alongside a
   third device (a key-based desktop) that mostly uses a key already.
   Confirming from just one working device during the dead-man countdown
   would miss that the other two are about to be locked out. `apply.sh` now
   audits this per device and gates the sshd stage on it; see "Before you
   run it" below.

## Why

sshd listens on all interfaces, and password authentication is still on.
That's the one real gap on this host, and it's what `apply.sh` fixes by
default: a drop-in that requires key-only, non-root auth, only once there's
at least one key to log in with — and only once every device that currently
logs in with a password has a key instead.

They deliberately don't call `omarchy setup security sshd`: that command's
firewall step opens SSH globally (not scoped to LAN/tailnet), and its key
step is interactive. This script reuses its validation pattern (`sshd -t`,
then `sshd -T` effective-config check, then reload-not-restart) without its
firewall or key steps.

They also don't touch Docker-published ports — a container published on
`0.0.0.0` bypasses ufw's own INPUT chain via Docker's `DOCKER-USER` iptables
chain. If `ufw-docker` is installed, that chain already lets RFC1918-ish
sources (LAN) through and blocks the rest; widening that to the tailnet for
a specific container is a separate, explicit choice
(`ufw-docker allow <container> <port>`), not something this script guesses
at.

## Before you run it

Run `./system/ssh-firewall/apply.sh --dry-run` first — it prints a
password-vs-publickey table per tailnet device (by name, never by IP) for
the last 30 days. Any device shown in red still logs in with a password and
would be locked out once sshd stops accepting passwords. Give each of those
a key before running `apply.sh` for real:

- **On a second laptop** (or any Linux/Mac device): generate a key if it
  doesn't have one yet, then copy it over (needs a password login to work once):
  ```sh
  ssh-keygen -t ed25519            # skip if ~/.ssh/id_ed25519 already exists
  ssh-copy-id lunav0@<this host's tailnet name>
  ```
- **On the phone** (Android): in your SSH app (Termux, or another SSH client
  app) generate a key — e.g. in Termux, `ssh-keygen -t ed25519` — then either
  run `ssh-copy-id lunav0@<this host's tailnet name>` from Termux, or copy
  the printed public key by hand and append it to `~/.ssh/authorized_keys`
  on this host.
- **Verify each device before trusting it**, from that device:
  ```sh
  ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no lunav0@<this host's tailnet name>
  ```
  If that logs in without a password prompt, the device is ready. If it
  fails, the key isn't authorized yet — don't run `apply.sh`'s sshd stage
  until it does.

Only once every device the audit flagged passes that check should you type
`keys-ready` when `apply.sh` asks for it.

## Run

```sh
cd ~/.dotfiles
./system/ssh-firewall/apply.sh --dry-run   # detect + print the plan (incl. the password audit), no sudo, no changes
sudo ./system/ssh-firewall/apply.sh        # sshd hardening only, by default
```

`apply.sh` prints the current state (ufw service, LAN CIDR read live from
`ip route`, existing SSH-related ufw rules, a listener inventory, the
30-day password-login audit) and the plan, then asks for confirmation
before each stage it's actually going to run.

### Default: sshd hardening only

With no flags, the only thing `apply.sh` can change is
`/etc/ssh/sshd_config.d/10-local-hardening.conf` (`PasswordAuthentication
no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`). It refuses to
write it at all if `authorized_keys` has no key.

If the password-login audit found any device still using a password,
`apply.sh` stops and requires you to type the literal word `keys-ready`
(not a plain y/N) before it will even offer the sshd stage — see "Before
you run it" above. Skip that step and it refuses and exits.

The drop-in is then validated with `sshd -t` and `sshd -T` before reloading,
and only reloads — never restarts. That reload is covered by its own
dead-man switch: apply.sh backs up whatever was at that path before
(nothing, on a first run), then after reloading sshd arms `sleep 300 &&
restore that previous state && reload sshd again`. The prompt names every
device the audit flagged — confirm a **fresh** login (a new session, not a
reused one) from **each** of them, not just one, by running from each
device:

```sh
ssh lunav0@<this host's tailnet name>
```

(`apply.sh` prints the actual name — it reads it live from `tailscale
status --json`'s `Self.DNSName`, falling back to plain `hostname`; it's
never hard-coded in the script.)

Press Enter once every one of those devices confirmed, to cancel the
restore. If you don't, the previous sshd auth config comes back on its own
after 5 minutes.

### Opt-in: LAN rules

```sh
sudo ./system/ssh-firewall/apply.sh --allow-lan-ssh    # + ufw limit SSH from the LAN CIDR
sudo ./system/ssh-firewall/apply.sh --allow-lan-mdns   # + ufw allow mDNS from the LAN CIDR
```

Each is independent and off unless passed. `--dry-run --allow-lan-ssh` (etc.)
shows what it would add without changing anything. Passing either arms the
ufw dead-man switch (`sleep 300 && ufw disable`) the same way the original
version of this script always did — confirm the same `ssh
lunav0@<this host's tailnet name>` test from another tailnet device, then
press Enter to cancel it.

## Rollback

```sh
./system/ssh-firewall/rollback.sh --dry-run
sudo ./system/ssh-firewall/rollback.sh
```

Removes the sshd drop-in, and any ufw rules tagged `dotfiles-ssh-firewall-*`
(present only if `apply.sh` was run with `--allow-lan-ssh`/`--allow-lan-mdns`
at some point). Everything else, including the pre-existing tailscale0 SSH
rule, is left alone — `apply.sh` never touches it either.
