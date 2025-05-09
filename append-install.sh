#!/usr/bin/env bash

set -e

# Resolve the path to this script to correctly reference base script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
BASE_SCRIPT="$SCRIPT_DIR/install.sh"

echo "📦 Running base setup first..."
bash "$BASE_SCRIPT"

echo "🎮 Installing NVIDIA extras and gaming tools..."

# NVIDIA Container Toolkit (from AUR, yay required)
yay -S --needed --noconfirm nvidia-container-toolkit

# Restart Docker for NVIDIA runtime
sudo systemctl restart docker

# Steam (Gaming)
sudo pacman -Sy --needed --noconfirm steam

# nvtop (GPU monitor)
sudo pacman -Sy --needed --noconfirm nvtop

echo "✅ Append setup complete."

