# ── lsl: listify a directory into a proper Python list (or DataFrame) ──
# Robust replacement for `list($(ls))` — which returns the captured string's
# *characters*, not filenames — and for `$(ls).split()`, which breaks on
# spaces/newlines in names. Reads the directory directly (os.scandir), so no
# `ls` output parsing is involved.
import os
from pathlib import Path


def lsl(path=".", *, all=False, dirs=None, paths=False, df=False):
    """List a directory as a sorted Python list — or a pandas DataFrame.

    path  : directory to list (default: current dir; ~ is expanded)
    all   : include dotfiles (like `ls -a`, minus `.`/`..`)
    dirs  : True → only directories, False → only files, None → both
    paths : return pathlib.Path objects instead of plain names (list mode)
    df    : return a DataFrame with columns name/type/size/modified instead
            of a list (needs pandas: `xpip install pandas`)

    Examples:
        lsl()                         # names in cwd
        lsl("~/.config", all=True)    # include dotfiles
        lsl(dirs=True)                # only directories
        for p in lsl(paths=True): ... # pathlib.Path objects

        d = lsl(df=True)              # DataFrame
        d.sort_values("size", ascending=False).head()
        d[d["type"] == "file"]
        d.set_index("name")["size"].sum()
    """
    base = os.path.expanduser(path)
    names, rows = [], []
    with os.scandir(base) as it:
        for e in it:
            if not all and e.name.startswith("."):
                continue
            if dirs is True and not e.is_dir():
                continue
            if dirs is False and not e.is_file():
                continue
            if df:
                st = e.stat(follow_symlinks=False)  # never raises on broken links
                if e.is_symlink():
                    kind = "link"
                elif e.is_dir():
                    kind = "dir"
                elif e.is_file():
                    kind = "file"
                else:
                    kind = "other"
                rows.append((e.name, kind, st.st_size, st.st_mtime))
            else:
                names.append(e.name)

    if df:
        try:
            import pandas as pd
        except ModuleNotFoundError as exc:
            raise ModuleNotFoundError(
                "lsl(df=True) needs pandas — run: xpip install pandas"
            ) from exc
        frame = pd.DataFrame(rows, columns=["name", "type", "size", "modified"])
        frame["modified"] = pd.to_datetime(frame["modified"], unit="s")
        return (
            frame.sort_values("name", key=lambda s: s.str.lower())
            .reset_index(drop=True)
        )

    names.sort(key=str.lower)
    if paths:
        return [Path(base) / name for name in names]
    return names
