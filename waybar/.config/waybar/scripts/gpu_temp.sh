#!/bin/bash

# Check if nvidia-smi is available
if command -v nvidia-smi &> /dev/null; then
    used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null)
    total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null)

    if [[ -n "$used" && -n "$total" && "$total" -gt 0 ]]; then
      used_gb=$(( (used + 1023) / 1024 ))
      total_gb=$(( (total + 1023) / 1024 ))
      vram_usage="${used_gb}/${total_gb} GB"
    else
      vram_usage="N/A"
    fi
    gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)

    if [[ -n "$gpu_temp" && -n "$gpu_usage" ]]; then
      echo "$vram_usage | GPU ${gpu_usage}% | ${gpu_temp}°C"
    else
      echo "N/A | GPU N/A | N/A"
    fi
else
    # Don't display anything if nvidia-smi is not available
    echo ""
fi