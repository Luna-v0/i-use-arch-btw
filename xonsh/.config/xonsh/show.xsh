# ── show: render a pandas DataFrame as a colored rich table ──
# Pairs with lsl(df=True):  show(lsl(df=True))
# Needs rich + pandas (xpip install rich pandas). Imports are lazy so this
# helper still loads if they're missing — only show() requires them.

_show_console = None  # cached Console (one per session)

# Explicit truecolor hex tuned for the deep-jade (#0a2018) background. Using
# literal hex (not ANSI names like "blue") guarantees contrast regardless of
# the terminal palette — the old "bold blue" dirs were near-invisible navy.
_PAL = {
    "header": "bold #4aff99",  # bright jade headers
    "index":  "#5f8472",       # muted, readable row numbers
    "dir":    "bold #4aff99",  # directories pop
    "file":   "#d4e8f5",       # filenames: bright white
    "type_f": "#33ff88",       # 'file' type label: green
    "num":    "#f4d03f",       # numerics (size): yellow
    "date":   "#86b3a3",       # dates: muted teal (readable, not dim)
}


def show(df, title=None, index=True):
    """Render a pandas DataFrame as a colored rich table (fresh table each call).

    Recognizes a file-listing 'type' column (dir/file) and colors accordingly;
    falls back to sensible styling (right-aligned + yellow numerics, muted
    dates) for any other DataFrame.

        show(lsl(df=True))
        show(df, title="report", index=False)
    """
    global _show_console
    try:
        import pandas as pd
        from rich.console import Console
        from rich.table import Table
        from rich.text import Text
        from rich import box
    except ModuleNotFoundError as exc:
        raise ModuleNotFoundError(
            "show() needs rich + pandas — run: xpip install rich pandas"
        ) from exc

    # force_terminal + truecolor so color never gets stripped under xonsh's stdout
    if _show_console is None:
        _show_console = Console(force_terminal=True, color_system="truecolor")

    table = Table(title=title, box=box.SIMPLE_HEAVY, header_style=_PAL["header"])

    if index:
        table.add_column("#", justify="right", style=_PAL["index"])
    for col in df.columns:
        justify = "right" if pd.api.types.is_numeric_dtype(df[col]) else "left"
        table.add_column(str(col), justify=justify)

    type_col = "type" if "type" in df.columns else None

    # Using Text objects (not "[bold]..." markup) so filenames containing
    # square brackets can't break or inject rich markup.
    for i, (_, row) in enumerate(df.iterrows()):
        is_dir = bool(type_col) and str(row[type_col]).lower() == "dir"
        cells = [Text(str(i), style=_PAL["index"])] if index else []
        for col in df.columns:
            val = str(row[col])
            if col == type_col:
                cells.append(Text(val, style=_PAL["dir"] if is_dir else _PAL["type_f"]))
            elif col == "name":
                cells.append(Text(val, style=_PAL["dir"] if is_dir else _PAL["file"]))
            elif col == "modified":
                cells.append(Text(val, style=_PAL["date"]))
            elif pd.api.types.is_numeric_dtype(df[col]):
                cells.append(Text(val, style=_PAL["num"]))
            else:
                cells.append(Text(val))
        table.add_row(*cells)

    _show_console.print(table)
