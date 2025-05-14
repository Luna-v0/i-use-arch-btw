#!/bin/bash

host_conf="$HOME/.config/hypr/$(hostname).conf"
target_conf="$HOME/.config/hypr/generated.conf"

if [[ -f "$host_conf" ]]; then
    cp "$host_conf" "$target_conf"
else
    echo "# No host config found for $(hostname)" > "$target_conf"
fi

