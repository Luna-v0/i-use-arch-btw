#!/bin/bash

# Set paths explicitly
output_dir="$HOME/Videos"
mkdir -p "$output_dir"

pid_file="/tmp/wf-recorder.pid"
log_file="/tmp/wf-recorder.log"

if [ -f "$pid_file" ]; then
    # Stop recording
    pid=$(cat "$pid_file")
    kill "$pid" && notify-send "📼 Screen recording stopped"
    rm -f "$pid_file"
else
    # Select region
    region=$(slurp)
    if [ -z "$region" ]; then
        notify-send "❌ No region selected. Cancelled."
        exit 1
    fi

    # Generate output filename
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    output_file="$output_dir/recording_$timestamp.mp4"

    # Start recording in background and save PID
    wf-recorder -g "$region" -f "$output_file" > "$log_file" 2>&1 &
    echo $! > "$pid_file"

    notify-send "🎥 Screen recording started"
fi

