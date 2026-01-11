# Tmux Configuration

This directory contains tmux configuration with TPM (Tmux Plugin Manager) and several useful plugins.

## Current Plugins

Your configuration includes the following plugins:

1. **tmux-resurrect** - Save and restore tmux sessions
   - Press `prefix + Ctrl-s` to save the current session
   - Press `prefix + Ctrl-r` to restore the last saved session
   - Sessions are saved to `~/.config/tmux/resurrect/`

2. **tmux-continuum** - Automatic save/restore of tmux sessions
   - Automatically saves sessions every 15 minutes
   - Automatically restores sessions on tmux server start (configured with `@continuum-restore 'on'`)

3. **tmux-sensible** - Sensible defaults for tmux (base settings)

4. **tmux-prefix-highlight** - Highlights when prefix key is pressed

5. **tmux-yank** - Better copy/paste functionality
   - Press `prefix + y` to copy the current pane's working directory
   - Works with system clipboard

## Installation

### 1. Install the plugins

After configuring tmux (or when you've added new plugins), install them:

1. Start or attach to a tmux session
2. Press `prefix + I` (capital I as in **I**nstall)
   - Your prefix key is `Ctrl-a` (configured in tmux.conf)

This will download and install all configured plugins.

### 2. Verify installation

After pressing `prefix + I`, you should see output indicating the plugins are being installed. Once complete, press `prefix` again to reload tmux.

## Usage

### Tmux Resurrect (Save/Restore Sessions)

**Save current session:**
```
prefix + Ctrl-s
```

**Restore last saved session:**
```
prefix + Ctrl-r
```

The restore command will list all saved sessions. Use arrow keys to navigate and Enter to select.

**Note:** Your current config has `@resurrect-capture-pane-contents 'off'` which means pane contents (scrollback) are not saved. Change this to `'on'` in tmux.conf if you want to save scrollback history.

### Continuum (Automatic Save/Restore)

- Sessions are automatically saved every 15 minutes
- Sessions are automatically restored when tmux server starts (if `@continuum-restore 'on'`)

You can also manually trigger saves:
```
prefix + Ctrl-s  (same as resurrect save)
```

### Managing Plugins

**Update plugins:**
- `prefix + U` - Update all plugins
- Navigate through plugins with arrow keys and press Enter to update selected ones

**Remove unused plugins:**
- `prefix + Alt-u` - Remove plugins not listed in config

**Install new plugins:**
1. Add `set -g @plugin 'username/plugin-name'` to `tmux.conf`
2. Press `prefix + I` to install
3. Reload config: `tmux source ~/.config/tmux/tmux.conf` or restart tmux

## Configuration

The main configuration file is at: `~/.config/tmux/tmux.conf`

Key settings:
- Prefix key: `Ctrl-a` (instead of default `Ctrl-b`)
- Mouse mode: Enabled
- History limit: 2000 lines
- Status bar: Top position
- Continuum restore: Enabled (`@continuum-restore 'on'`)
- Resurrect pane contents: Disabled (`@resurrect-capture-pane-contents 'off'`)

## Additional Popular Plugins (Optional)

If you want to add more plugins, here are some popular ones:

- `tmux-plugins/tmux-battery` - Battery status in status bar
- `tmux-plugins/tmux-cpu` - CPU usage in status bar
- `tmux-plugins/tmux-net-speed` - Network speed in status bar
- `tmux-plugins/tmux-sidebar` - File browser sidebar (`prefix + \`)
- `tmux-plugins/tmux-open` - Open highlighted text in default app (`prefix + o`)
- `tmux-plugins/tmux-copycat` - Enhanced search functionality (`prefix + /`)

To add any of these:
1. Add `set -g @plugin 'tmux-plugins/plugin-name'` to `tmux.conf`
2. Press `prefix + I` to install

## Troubleshooting

**Plugins not loading?**
- Make sure TPM is installed: the `run` command at the bottom of tmux.conf should point to the correct path
- After adding plugins, press `prefix + I` to install them
- Reload config: `tmux source ~/.config/tmux/tmux.conf`

**Resurrect not working?**
- Check that the plugin is installed in `~/.config/tmux/plugins/tmux-resurrect/`
- Make sure you're saving sessions with `prefix + Ctrl-s` before trying to restore
- Check the resurrect directory: `~/.config/tmux/resurrect/`

**TPM key bindings not working?**
- Make sure you're pressing the correct prefix key (`Ctrl-a` in your config)
- Try reloading: `tmux source ~/.config/tmux/tmux.conf`

