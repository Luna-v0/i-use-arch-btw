#!/bin/bash

# if hostname is fantasy2
if [[ "$(hostname)" == "Fantasy2" ]]; then
    used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)

    if [[ -n "$used" && -n "$total" && "$total" -gt 0 ]]; then
      used_gb=$(( (used + 1023) / 1024 ))
      total_gb=$(( (total + 1023) / 1024 ))
      vram_usage="${used_gb}/${total_gb} GB"
    else
      vram_usage="N/A"
    fi
    gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)


    echo "$vram_usage | GPU ${gpu_usage}% | $gpu_temp°C"
fi
