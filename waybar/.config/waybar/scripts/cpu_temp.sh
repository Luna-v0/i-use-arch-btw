#!/bin/bash

read -r used_mb total_mb <<< $(free -m | awk '/Mem:/ {print $3, $2}')

# Convert to GiB (rounded up)
used_gb=$(( (used_mb + 1023) / 1024 ))
total_gb=$(( (total_mb + 1023) / 1024 ))
ram_usage="${used_gb}/${total_gb} GB"

# CPU usage (rounded to integer)
cpu_usage=$(mpstat 1 1 | awk '/Average/ {printf "%.0f", 100 - $NF}')


# CPU temp rounded - try different sensor types
cpu_temp=""
if command -v sensors &> /dev/null; then
    # Try AMD (k10temp)
    cpu_temp=$(sensors 2>/dev/null | awk '/k10temp-pci-00c3/,/^$/' | grep 'Tctl' | awk '{printf("%d°C", $2)}')
    # Try Intel (coretemp) if AMD didn't work
    if [[ -z "$cpu_temp" ]]; then
        cpu_temp=$(sensors 2>/dev/null | awk '/coretemp-isa-0000/,/^$/' | grep 'Package id 0' | awk '{printf("%d°C", $4)}')
    fi
fi

# Fallback if sensors didn't work
if [[ -z "$cpu_temp" ]]; then
    cpu_temp="N/A"
fi

echo "$ram_usage | CPU $cpu_usage% | $cpu_temp"