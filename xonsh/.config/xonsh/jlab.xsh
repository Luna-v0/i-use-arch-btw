# ── Multi-project Jupyter + Claude Code MCP launcher (xonsh port) ──
# Loaded from rc.xsh. Provides: jlab, jlab-ls, jlab-stop, jlab-reset, jlab-clean
#
# `jlab` installs a core Jupyter stack into the current project (via uv) and
# launches JupyterLab on a fixed per-repo port. The collaboration + Claude MCP
# bridge needs Python >= 3.10; on older projects (e.g. 3.8) it is skipped
# automatically. Pass `jlab --no-mcp` to skip it explicitly.
#
# Run `jlab --help` for the full flag list. Any flag jlab doesn't know is
# forwarded verbatim to `jupyter lab`.
import argparse
import os
import socket
import hashlib
import secrets
import shutil
import subprocess
from pathlib import Path

_JLAB_DIR = Path(os.path.expanduser("~/.config/jlab"))

# Core stack — resolves on older Pythons too (incl. 3.8).
_JLAB_CORE = [
    "jupyterlab", "ipykernel", "jupyterlab-lsp", "python-lsp-server[all]",
    "jupyterlab-git", "jupytext", "lckr-jupyterlab-variableinspector",
    "ipywidgets", "jupyterlab-vim", "catppuccin-jupyterlab",
]
# Real-time collaboration + MCP bridge — requires Python >= 3.10.
_JLAB_MCP = ["jupyter-collaboration", "jupyter-mcp-tools", "pycrdt"]


def _jlab_port_free(port, host="127.0.0.1"):
    """True when the TCP port is free on `host`."""
    s = socket.socket()
    try:
        return s.connect_ex((host, int(port))) != 0
    except socket.gaierror:
        return True          # can't resolve → let jupyter report the real error
    finally:
        s.close()


def _jlab_probe_host(ip):
    """Host to use when checking whether the port is already taken.

    0.0.0.0 / :: mean "all interfaces", which aren't connectable addresses —
    probe loopback instead.
    """
    return {"0.0.0.0": "127.0.0.1", "::": "::1", "": "127.0.0.1"}.get(ip, ip)


def _jlab_state():
    """Load (or assign-once) this repo's fixed PORT + TOKEN, keyed by repo path."""
    _JLAB_DIR.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1(os.path.realpath(".").encode()).hexdigest()[:12]
    f = _JLAB_DIR / f"{key}.env"
    if not f.exists():
        used = {
            line[len("PORT="):]
            for ef in _JLAB_DIR.glob("*.env")
            for line in ef.read_text().splitlines()
            if line.startswith("PORT=")
        }
        port = 8888
        while not _jlab_port_free(port) or str(port) in used:
            port += 1
        f.write_text(f"PORT={port}\nTOKEN={secrets.token_hex(16)}\n")
        f.chmod(0o600)
    kv = dict(
        line.split("=", 1) for line in f.read_text().splitlines() if "=" in line
    )
    return kv["PORT"], kv["TOKEN"]


def _jlab_have(mod):
    """True if the current project's env can import `mod`."""
    return subprocess.run(
        ["uv", "run", "python", "-c", f"import {mod}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def _jlab_uv_add(pkgs):
    """`uv add --dev <pkgs>` — returns True on success (never raises)."""
    return subprocess.run(["uv", "add", "--dev", *pkgs]).returncode == 0


def _jlab_parser():
    p = argparse.ArgumentParser(
        prog="jlab",
        description=(
            "Launch JupyterLab for the current uv project on a fixed per-repo "
            "port, installing the Jupyter stack with `uv add --dev` on first "
            "use. Port and token are assigned once per repo path and reused."
        ),
        epilog=(
            "Unrecognised flags are forwarded verbatim to `jupyter lab`, e.g.\n"
            "  jlab --ip 0.0.0.0 --ServerApp.allow_origin='*'\n"
            "  jlab --no-mcp --notebook-dir notebooks\n\n"
            "Related commands: jlab-ls, jlab-stop, jlab-reset, jlab-clean."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--ip", "--address", dest="ip", metavar="ADDR", default="127.0.0.1",
        help="address to bind to (jupyter's --ip). Use 0.0.0.0 to expose the "
             "Lab on the LAN. Default: %(default)s",
    )
    p.add_argument(
        "--port", type=int, metavar="N", default=None,
        help="override this repo's assigned port for one run "
             "(the stored port is left untouched)",
    )
    p.add_argument(
        "--browser", action="store_true",
        help="let Jupyter open a browser (default: --no-browser)",
    )
    p.add_argument(
        "--no-mcp", "--core", dest="mcp", action="store_false",
        help="skip the collaboration/MCP stack and the per-repo Claude MCP entry",
    )
    p.add_argument(
        "--force", action="store_true",
        help="start even if something is already listening on the port",
    )
    p.add_argument(
        "--no-rtc", dest="rtc", action="store_false",
        help="disable real-time collaboration. Lab then reads every file "
             "straight from disk, so it can never show you a stale in-memory "
             "copy — but the Jupyter MCP bridge needs RTC, so this likely "
             "breaks `claude`'s notebook editing",
    )
    p.add_argument(
        "--squash", type=int, metavar="SECS", default=86400,
        help="squash a document's RTC edit history after this many seconds of "
             "inactivity, so .jupyter_ystore.db stops growing without bound. "
             "0 keeps full history (upstream default). Default: %(default)s",
    )
    return p


def _jlab(args):
    parser = _jlab_parser()
    try:
        ns, extra = parser.parse_known_args(args)
    except SystemExit as exc:      # -h/--help, or a bad value
        return exc.code or 0

    port, token = _jlab_state()
    if ns.port is not None:
        port = str(ns.port)
    want_mcp = ns.mcp
    if want_mcp and not ns.rtc:
        print("jlab: --no-rtc disables the collaboration layer the Jupyter MCP "
              "bridge rides on; pair it with --no-mcp if `claude` misbehaves.")

    # Core Jupyter stack (works on older Pythons).
    if not _jlab_have("jupyterlab"):
        print("jlab: installing core Jupyter packages …")
        if not _jlab_uv_add(_JLAB_CORE):
            print("jlab: could not install the core Jupyter stack (see error above).")
            return 1

    # Collaboration + MCP stack (needs Python >= 3.10). If the project's Python
    # can't satisfy it, skip gracefully and run a plain Lab.
    if want_mcp and not _jlab_have("jupyter_collaboration"):
        print("jlab: adding collaboration/MCP packages …")
        if not _jlab_uv_add(_JLAB_MCP):
            print("jlab: this project's Python can't satisfy the MCP/collaboration "
                  "stack (needs >= 3.10) — continuing WITHOUT MCP.")
            want_mcp = False

    # Per-project MCP — LOCAL scope: only exists inside this repo.
    if want_mcp and shutil.which("claude"):
        present = subprocess.run(
            ["claude", "mcp", "get", "jupyter"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode == 0
        if not present:
            subprocess.run([
                "claude", "mcp", "add", "--scope", "local",
                "--env", f"JUPYTER_URL=http://localhost:{port}",
                "--env", f"JUPYTER_TOKEN={token}",
                "--env", "ALLOW_IMG_OUTPUT=true",
                "jupyter", "--", "uvx", "jupyter-mcp-server@latest",
            ])

    probe = _jlab_probe_host(ns.ip)
    if not ns.force and not _jlab_port_free(port, probe):
        print(f"Lab for this project already running on :{port} "
              f"(use --force to start anyway)")
        return

    tag = "(run `claude` in this repo)" if want_mcp else "(no MCP)"
    shown = "localhost" if probe in ("127.0.0.1", "::1") else ns.ip
    print(f"Lab → http://{shown}:{port}/lab?token={token}  {tag}")
    if ns.ip not in ("127.0.0.1", "localhost", "::1"):
        print("jlab: binding to a non-loopback address — the token above is the "
              "only thing guarding this Lab.")
    # JupyterLab is in the foreground process group, so it handles its own Ctrl-C.
    rtc = []
    if not ns.rtc:
        rtc = ["--YDocExtension.disable_rtc=True"]
    elif ns.squash > 0:
        rtc = [f"--SQLiteYStore.squash_after_inactivity_of={ns.squash}"]
    subprocess.run([
        "uv", "run", "jupyter", "lab",
        "--port", str(port),
        "--ip", ns.ip,
        "--IdentityProvider.token", token,
        *([] if ns.browser else ["--no-browser"]),
        *rtc,
        *extra,
    ])


def _jlab_ls(args):
    """List the Jupyter servers this project's env knows about."""
    subprocess.run(["uv", "run", "jupyter", "server", "list"])


def _jlab_stop(args):
    """Stop the Lab running on this repo's assigned port."""
    port, _ = _jlab_state()
    if args and args[0] in ("-h", "--help"):
        print("usage: jlab-stop        # stops this repo's Lab "
              f"(currently :{port})")
        return
    if subprocess.run(["uv", "run", "jupyter", "server", "stop", str(port)]).returncode == 0:
        print(f"stopped :{port}")


def _jlab_reset(args):
    """Drop this repo's local Claude MCP entry; the next `jlab` re-adds it."""
    if args and args[0] in ("-h", "--help"):
        print("usage: jlab-reset       # removes this repo's `jupyter` MCP entry")
        return
    subprocess.run(["claude", "mcp", "remove", "jupyter"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("removed this repo's MCP; next `jlab` re-adds it")


def _jlab_clean(args):
    """Delete the RTC ystore(s) under this repo.

    The ystore holds JupyterLab's collaborative *edit history*, not your files —
    notebooks are flushed to disk about a second after every change. Dropping it
    forces Lab to re-read every document from disk on next open, which is the
    cure when Lab is showing a stale version of a file you changed elsewhere.
    """
    ap = argparse.ArgumentParser(
        prog="jlab-clean",
        description=_jlab_clean.__doc__.split("\n\n")[1].replace("\n    ", " "),
    )
    ap.add_argument("--yes", "-y", action="store_true",
                    help="actually delete (without this, just lists what it found)")
    try:
        ns = ap.parse_args(args)
    except SystemExit as exc:
        return exc.code or 0

    root = Path(os.path.realpath("."))
    found = sorted(root.rglob(".jupyter_ystore.db*"))
    if not found:
        print(f"jlab-clean: no ystore under {root}")
        return

    port, _ = _jlab_state()
    running = not _jlab_port_free(port)
    total = sum(f.stat().st_size for f in found)
    for f in found:
        print(f"  {f.stat().st_size / 1e6:9.1f} MB  {f.relative_to(root)}")
    print(f"  {total / 1e6:9.1f} MB  total")

    if running:
        print(f"jlab: a Lab is still running on :{port} — stop it first "
              f"(`jlab-stop`), otherwise it will just rewrite these.")
        return 1
    if not ns.yes:
        print("jlab-clean: re-run with --yes to delete.")
        return
    for f in found:
        f.unlink()
    print(f"deleted {len(found)} file(s), freed {total / 1e6:.1f} MB")


aliases["jlab"] = _jlab
aliases["jlab-ls"] = _jlab_ls
aliases["jlab-stop"] = _jlab_stop
aliases["jlab-reset"] = _jlab_reset
aliases["jlab-clean"] = _jlab_clean
