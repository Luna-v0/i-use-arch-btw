#!/bin/bash

# Hyprland Global Workspace Switcher
# This script switches all connected monitors to the same workspace
# regardless of whether the workspace exists or not.

# --- Configuration ---

# Get workspace number from argument
ws="$1"

# Validate input
if [[ -z "$ws" || ! "$ws" =~ ^[0-9]+$ ]]; then
  notify-send "Hyprland Global Workspace" "Usage: global-workspace.sh <number>"
  exit 1
fi

# --- Execution ---

# Get list of all connected monitor names
monitors=$(hyprctl monitors -j | jq -r '.[].name')

# Loop through each monitor and set its workspace
for mon in $monitors; do
  hyprctl dispatch "workspace $ws,monitor:$mon"
done

# Optional: you can uncomment this to send a confirmation notification
# notify-send "Hyprland" "Switched all monitors to workspace $ws"

