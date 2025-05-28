#!/usr/bin/env bash

set -e

echo "🔧 Installing base packages..."

# Slack & Discord (from AUR, assuming yay is installed)
yay -S --needed --noconfirm slack-desktop discord zoom-us

# Docker & Docker Compose
sudo pacman -S --needed --noconfirm docker docker-compose
sudo systemctl enable --now docker.service
sudo usermod -aG docker "$USER"

# Node Version Manager (nvm) setup for Zsh
if [ ! -d "$HOME/.nvm" ]; then
  git clone https://github.com/nvm-sh/nvm.git ~/.nvm
  cd ~/.nvm && git checkout v0.39.7
  echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
  echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc
  export NVM_DIR="$HOME/.nvm"
  source "$NVM_DIR/nvm.sh"
else
  export NVM_DIR="$HOME/.nvm"
  source "$NVM_DIR/nvm.sh"
fi

# Install Node.js (LTS) + npm + pnpm
nvm install --lts
npm install -g pnpm

# uv (Python fast package manager)
curl -Ls https://astral.sh/uv/install.sh | bash

# GUI tools
sudo pacman -S --needed --noconfirm \
  wofi waybar mako neovim  stow \
  bitwarden-cli wf-recorder slurp grim btop tree

# VPN support
sudo pacman -S --needed --noconfirm openvpn networkmanager-openvpn

echo "✅ Base setup complete. You may need to log out/in to apply Docker group changes."

