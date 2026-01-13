#!/usr/bin/env python3
import re
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Tree, Static
from textual.containers import Container, Vertical
from textual.binding import Binding
from hyprpy import Hyprland

class HyprlandTree(App):
    """A professional TUI for visualizing Hyprland state."""

    CSS = """
    Screen {
        layout: vertical;
    }

    #stats {
        height: 3;
        border: solid $accent;
        padding: 0 1;
        margin-bottom: 1;
    }

    Tree {
        padding: 1;
        border: solid $accent;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh", "Refresh Now"),
        Binding("enter", "focus_selected", "Focus Selected"),
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Static("Loading...", id="stats")
        yield Tree("Hyprland System State")
        yield Footer()

    def on_mount(self) -> None:
        """Called when the app starts."""
        # Robustness Fix: Query by Type (Tree) instead of ID.
        # This guarantees it finds the widget we just yielded.
        self.tree_widget = self.query_one(Tree)
        self.stats = self.query_one("#stats", Static)
        self.tree_widget.root.expand()

        # Store node metadata for interaction
        self.node_metadata = {}

        self.refresh_data()
        self.set_interval(2.0, self.refresh_data)

    def action_refresh(self) -> None:
        """Manual refresh action."""
        self.refresh_data()

    def clean_chrome_app_name(self, wm_class: str) -> str:
        """Extract clean name from Chrome web app class (chrome-NAME.com-...)."""
        # Pattern: chrome-NAME.com... or chrome-subdomain.NAME.com... -> NAME
        if wm_class.startswith('chrome-'):
            # Remove 'chrome-' prefix
            domain_part = wm_class[7:]  # Skip 'chrome-'

            # Split by dots and get domain parts
            parts = domain_part.split('.')

            # Extract the main domain name (second-to-last part, before TLD)
            # Examples:
            #   github.com -> parts[-2] = github
            #   music.youtube.com -> parts[-2] = youtube
            #   web.whatsapp.com -> parts[-2] = whatsapp
            #   app.slack.com -> parts[-2] = slack
            if len(parts) >= 2:
                # Get the part before the TLD (.com, .org, etc.)
                main_domain = parts[-2]
                return main_domain.capitalize()

        return wm_class

    def action_focus_selected(self) -> None:
        """Focus the selected window or workspace in Hyprland."""
        cursor_node = self.tree_widget.cursor_node
        if cursor_node is None:
            return

        node_id = id(cursor_node)
        metadata = self.node_metadata.get(node_id)

        if not metadata:
            return

        try:
            instance = Hyprland()

            if metadata['type'] == 'window':
                # Focus window by address
                instance.dispatch(f"focuswindow address:{metadata['address']}")
                self.notify(f"Focused window: {metadata['title']}")

            elif metadata['type'] == 'workspace':
                # Switch to workspace
                instance.dispatch(f"workspace {metadata['id']}")
                self.notify(f"Switched to workspace: {metadata['name']}")

        except Exception as e:
            self.notify(f"Error: {e}", severity="error")

    def refresh_data(self) -> None:
        """Fetches data using hyprpy and rebuilds the tree."""
        try:
            instance = Hyprland()
            monitors = instance.get_monitors()
            workspaces = instance.get_workspaces()
            active_window = instance.get_active_window()
        except Exception as e:
            # Fallback if Hyprland isn't running or API fails
            self.tree_widget.root.label = f"Error: {e}"
            self.stats.update(f"Error: {e}")
            return

        # Get active window address for focused window highlighting
        focused_address = getattr(active_window, 'address', None) if active_window else None

        self.tree_widget.clear()
        self.tree_widget.root.label = "Hyprland System State"

        # Clear metadata for new tree
        self.node_metadata.clear()

        # Calculate statistics
        total_windows = 0
        total_workspaces = len(workspaces)

        # 1. Iterate Monitors
        for monitor in monitors:
            m_name = monitor.name
            m_width = monitor.width
            m_height = monitor.height

            mon_label = f"[bold cyan]{m_name}[/bold cyan] ({m_width}x{m_height})"
            mon_node = self.tree_widget.root.add(mon_label, expand=True, allow_expand=False)

            # 2. Filter Workspaces for this Monitor
            mon_workspaces = []
            for ws in workspaces:
                # Get monitor name from workspace
                ws_mon_name = ws.monitor_name

                if ws_mon_name == m_name:
                    mon_workspaces.append(ws)

            mon_workspaces.sort(key=lambda w: w.id)

            for ws in mon_workspaces:
                # Determine active workspace ID from monitor
                active_ws_id = monitor.active_workspace_id

                is_active = (ws.id == active_ws_id)

                # Get windows and count them
                windows = ws.windows
                window_count = len(windows)
                total_windows += window_count

                if is_active:
                    ws_label = f"[bold green]Workspace {ws.name}[/bold green] (ID: {ws.id}) [[green]{window_count} windows[/green]]"
                else:
                    ws_label = f"Workspace {ws.name} (ID: {ws.id}) [{window_count} windows]"

                ws_node = mon_node.add(ws_label, expand=True, allow_expand=False)

                # Store workspace metadata for interaction
                self.node_metadata[id(ws_node)] = {
                    'type': 'workspace',
                    'id': ws.id,
                    'name': ws.name
                }

                # 3. Iterate Windows
                if not windows:
                    ws_node.add("Empty", allow_expand=False)

                for win in windows:
                    title = win.title if win.title else 'No Title'
                    if len(title) > 50:
                        title = title[:47] + "..."

                    wm_class = win.wm_class if win.wm_class else 'Unknown'
                    # Clean Chrome web app names
                    wm_class = self.clean_chrome_app_name(wm_class)

                    is_floating = win.is_floating
                    is_fullscreen = win.is_fullscreen
                    win_address = win.address

                    # Check if this is the focused window
                    is_focused = (win_address == focused_address)

                    # Build window label with color coding only
                    # Priority: focused > fullscreen > floating > normal
                    if is_focused:
                        win_label = f"[bold magenta]{wm_class}[/bold magenta]: [magenta]{title}[/magenta]"
                    elif is_fullscreen:
                        win_label = f"[bold red]{wm_class}[/bold red]: [red]{title}[/red]"
                    elif is_floating:
                        win_label = f"[yellow]{wm_class}[/yellow]: {title}"
                    else:
                        win_label = f"{wm_class}: {title}"

                    win_node = ws_node.add(win_label, allow_expand=False)

                    # Store window metadata for interaction
                    self.node_metadata[id(win_node)] = {
                        'type': 'window',
                        'address': win_address,
                        'title': title,
                        'class': wm_class
                    }

        # Update statistics panel
        self.stats.update(
            f"📊 Monitors: {len(monitors)} | Workspaces: {total_workspaces} | Windows: {total_windows}"
        )

if __name__ == "__main__":
    app = HyprlandTree()
    app.run()
