# ── xpip / xpy: target the xonsh environment itself ──
# xonsh's REPL runs on its own env (~/.local/xonsh-env), so to make a package
# importable AT THE PROMPT you must install it into THAT env — not a project
# venv. These wrap the env's own pip/python so you never type the full path:
#
#   xpip install pandas        # add a package to the xonsh shell env
#   xpip uninstall pandas
#   xpip list
#   xpy                        # python REPL / -c for the xonsh env
#
# (For project work use `uv run python` instead — see this package's README.)
import sys

# sys.executable is the xonsh env's python, wherever the env lives.
aliases["xpip"] = [sys.executable, "-m", "pip"]
aliases["xpy"] = [sys.executable]
