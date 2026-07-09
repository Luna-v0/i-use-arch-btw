# ── Multi-project Jupyter + Claude Code MCP launcher (xonsh port) ──
# Loaded from rc.xsh. Provides: jlab, jlab-ls, jlab-stop, jlab-reset
#
# `jlab` installs a core Jupyter stack into the current project (via uv) and
# launches JupyterLab on a fixed per-repo port. The collaboration + Claude MCP
# bridge needs Python >= 3.10; on older projects (e.g. 3.8) it is skipped
# automatically. Pass `jlab --no-mcp` to skip it explicitly.
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


def _jlab_port_free(port):
    """True when the TCP port is free on localhost."""
    s = socket.socket()
    try:
        return s.connect_ex(("127.0.0.1", int(port))) != 0
    finally:
        s.close()


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


def _jlab(args):
    want_mcp = not ({"--no-mcp", "--core"} & set(args))
    port, token = _jlab_state()

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

    if not _jlab_port_free(port):
        print(f"Lab for this project already running on :{port}")
        return

    tag = "(run `claude` in this repo)" if want_mcp else "(no MCP)"
    print(f"Lab → http://localhost:{port}/lab?token={token}  {tag}")
    # JupyterLab is in the foreground process group, so it handles its own Ctrl-C.
    subprocess.run([
        "uv", "run", "jupyter", "lab", "--port", str(port),
        "--IdentityProvider.token", token, "--no-browser",
    ])


def _jlab_ls(args):
    subprocess.run(["uv", "run", "jupyter", "server", "list"])


def _jlab_stop(args):
    port, _ = _jlab_state()
    if subprocess.run(["uv", "run", "jupyter", "server", "stop", str(port)]).returncode == 0:
        print(f"stopped :{port}")


def _jlab_reset(args):
    subprocess.run(["claude", "mcp", "remove", "jupyter"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("removed this repo's MCP; next `jlab` re-adds it")


aliases["jlab"] = _jlab
aliases["jlab-ls"] = _jlab_ls
aliases["jlab-stop"] = _jlab_stop
aliases["jlab-reset"] = _jlab_reset
