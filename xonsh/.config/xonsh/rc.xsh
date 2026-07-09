# ~/.config/xonsh/rc.xsh  — xonsh run-control file (this is xonsh code)

import os
import shutil

# ---- Environment ---------------------------------------------------------
$EDITOR = "nvim"          # change to the user's preferred editor
$VISUAL = $EDITOR
$PAGER  = "less"

$XONSH_HISTORY_SIZE = (10000, "commands")
$HISTCONTROL = {"ignoredups", "ignoreerr"}
$AUTO_CD = True
$XONSH_SHOW_TRACEBACK = True
$XONSH_AUTOPAIR = True

# Make sure ~/.local/bin is on PATH (tmux launches xonsh non-login)
_localbin = os.path.expanduser("~/.local/bin")
if _localbin not in $PATH:
    $PATH.insert(0, _localbin)

# ---- Ghostty/tmux integration --------------------------------------------
# Emit OSC 7 (current working directory) so new tabs/splits inherit the dir.
# Harmless under tmux; useful for bare Ghostty surfaces. Host computed once.
_osc7_host = $(hostname).strip()
@events.on_chdir
def _osc7_on_cd(olddir, newdir, **kw):
    import urllib.parse
    path = urllib.parse.quote(newdir)
    print(f"\033]7;file://{_osc7_host}{path}\033\\", end="", flush=True)

# ---- Xontribs (installed via the xonsh venv) -----------------------------
xontrib load vox            # built-in: Python virtualenv management
xontrib load coreutils      # built-in: extra coreutils
xontrib load zoxide         # needs the zoxide binary
xontrib load back2dir
xontrib load abbrevs
xontrib load cmd_done       # from xontrib-cmd-durations

# fish_completer needs the `fish` binary; load only if present so the rc
# never errors when fish isn't installed yet.
if shutil.which("fish"):
    xontrib load fish_completer

# ---- Abbreviations (need the abbrevs xontrib) ----------------------------
abbrevs["gst"] = "git status"
abbrevs["gco"] = "git checkout"
abbrevs["gp"]  = "git push"
abbrevs["gl"]  = "git pull"

# ---- Aliases -------------------------------------------------------------
aliases["ll"]   = "ls -lah --color=auto"
aliases["la"]   = "ls -A"
aliases["grep"] = "grep --color=auto"

def _mkcd(args):
    if not args:
        print("usage: mkcd <dir>")
        return 1
    os.makedirs(args[0], exist_ok=True)
    cd @(args[0])
aliases["mkcd"] = _mkcd

# ---- Helper scripts ------------------------------------------------------
# Auto-load every ~/.config/xonsh/*.xsh helper (jlab, lsl, …) except this rc.
# Drop a new .xsh file in that dir and it loads on next session — no rc edit.
import glob
for _f in sorted(glob.glob(os.path.expanduser("~/.config/xonsh/*.xsh"))):
    if os.path.basename(_f) != "rc.xsh":
        source @(_f)

# ---- Command-line syntax highlighting ------------------------------------
# On the green background, several default token colors (operators, punctuation,
# comments) are near-invisible — e.g. the `=` in `df=True`. Force the
# low-contrast tokens to bright, high-contrast colors.
# Register a custom style (instead of $XONSH_STYLE_OVERRIDES) so only the style
# NAME becomes an env var — a token dict in $XONSH_STYLE_OVERRIDES doesn't
# round-trip through xonsh's env detyping and emits a RuntimeWarning.
from pygments.token import (Comment, Keyword, Name, Number, Operator,
                            Punctuation, String)
from xonsh.pyghooks import register_custom_pygments_style
register_custom_pygments_style("forest", {
    Operator:     "#f5d76e",          # = + - * / | & etc.  -> bright yellow
    Punctuation:  "#b8d4e3",          # ( ) , : [ ] { }     -> normal fg tone
    Comment:      "#7fae97 italic",   # readable sage
    Keyword:      "#ff8b8b bold",     # import/for/in/True/False -> coral
    Name.Builtin: "#5ef1e0",          # print, len, ...     -> aqua
    Number:       "#f4d03f",          # yellow
    String:       "#9be7a8",          # soft green
})
$XONSH_COLOR_STYLE = "forest"

# ---- Prompt --------------------------------------------------------------
# Use starship — the same prompt as bash (config at ~/.config/starship.toml).
# Guarded so the rc still works on a machine without starship installed.
if shutil.which("starship"):
    execx($(starship init xonsh))
