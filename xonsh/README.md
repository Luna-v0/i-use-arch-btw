# 🐚 xonsh

[xonsh](https://xon.sh/) is the interactive shell used **inside tmux panes**.

It is **not** the login shell (`$SHELL` stays `/usr/bin/bash`) and is **not** set via
`chsh` — xonsh is not POSIX-compatible, so making it the login shell can break display
managers, SSH, and scripts. Instead, tmux launches it per pane via `default-command`.

## Launch chain

```
Hyprland SUPER+RETURN → ghostty -e tmux a -t main → tmux pane → default-command → xonsh
```

`tmux/.config/tmux/tmux.conf` sets:

```tmux
set -g default-command "$HOME/.local/xonsh-env/bin/xonsh"
```

`default-command` (not `default-shell`) is used deliberately so `$SHELL` remains `bash`
and POSIX scripts/tools keep working. New panes run xonsh; existing panes stay on bash
until recreated (or run `exec xonsh`).

## Required system packages (pacman)

```bash
sudo pacman -S --needed fish zoxide fzf
```

- `zoxide` — `z <partial>` directory jumping (xontrib-zoxide).
- `fzf` — fuzzy finder used by completions.
- `fish` — only needed for the `fish_completer` xontrib (rich external-command
  completions). `rc.xsh` loads `fish_completer` **only if the `fish` binary exists**,
  so the config works with or without it.

## xonsh environment (not a pacman package)

xonsh lives in a standalone **Python 3.12** environment at `~/.local/xonsh-env` (kept
out of the system Python — both because of PEP 668 and so the shell doesn't ride the
system's bleeding-edge Python, which often lacks wheels for pandas/numpy/etc.). Built
with `uv` (which provides the pinned 3.12). To recreate it on a new machine:

```bash
# --seed installs pip into the venv so the `xpip` helper works.
uv venv --seed --python 3.12 "$HOME/.local/xonsh-env"
uv pip install --python "$HOME/.local/xonsh-env/bin/python" \
    'xonsh[full]' \
    xontrib-zoxide xontrib-fish-completer xontrib-abbrevs xontrib-back2dir \
    xontrib-cmd-durations xontrib-vox \
    pandas rich      # data/scratch packages importable at the xonsh prompt
# NOTE: a venv is NOT relocatable — build it directly at the final path
# (its scripts hardcode an absolute python shebang); don't `mv` it afterward.
# xonsh's REPL runs on THIS env, so `import pandas` resolves here, not in any
# project venv. For project analysis use `uv run python` instead.
ln -sf "$HOME/.local/xonsh-env/bin/xonsh" "$HOME/.local/bin/xonsh"
# (optional) register as a known shell — does NOT change the login shell:
grep -qxF "$HOME/.local/xonsh-env/bin/xonsh" /etc/shells || \
    echo "$HOME/.local/xonsh-env/bin/xonsh" | sudo tee -a /etc/shells
```

> Note: `vox` and a few others were split out of xonsh core into separate
> `xontrib-*` packages, hence the explicit `xontrib-vox`. `coreutils` is still bundled.
> Do **not** install `xontrib-bashisms` — upstream advises against it.

## Config

`.config/xonsh/rc.xsh` — environment, PATH, OSC 7 cwd reporting, xontrib loads,
abbreviations (`gst`, `gco`, `gp`, `gl`), aliases (`ll`, `la`, `mkcd`), the
[starship](https://starship.rs/) prompt (shared with bash, via
`~/.config/starship.toml`), and auto-loading of every other
`~/.config/xonsh/*.xsh` helper.

### Helper scripts (auto-loaded)

- `jlab.xsh` — `jlab` / `jlab-ls` / `jlab-stop` / `jlab-reset` per-project Jupyter + Claude MCP.
  Installs a **core** Jupyter stack (works on Python 3.8+); the collaboration + MCP
  bridge needs Python ≥3.10 and is **auto-skipped** on older projects (or via
  `jlab --no-mcp`), so Lab still launches.
- `lsl.xsh` — `lsl()` returns a directory's entries as a proper Python list
  (robust replacement for `list($(ls))`, which yields characters). `lsl(df=True)`
  returns a pandas DataFrame (`name`/`type`/`size`/`modified`) for sorting/filtering.
- `xpip.xsh` — `xpip` / `xpy` target the xonsh env itself, so `xpip install pandas`
  makes a package importable at the prompt (the REPL runs on `~/.local/xonsh-env`).
- `show.xsh` — `show(df)` renders a pandas DataFrame as a colored rich table
  (dir/file aware). Pairs with lsl: `show(lsl(df=True))`. Needs `rich` + `pandas`.

## Rollback

```bash
# Revert tmux panes to bash:
sed -i '/default-command.*xonsh/d' ~/.config/tmux/tmux.conf && tmux source-file ~/.config/tmux/tmux.conf
# Remove xonsh entirely:
rm -rf ~/.local/xonsh-env ~/.local/bin/xonsh
```
