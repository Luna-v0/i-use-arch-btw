#!/usr/bin/env bash

set -e

echo "🔧 Installing base packages..."

# Slack & Discord (from AUR, assuming yay is installed)
yay -S --needed --noconfirm slack-desktop discord zoom-us vivaldi-bin

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
npm install -g pnpm zx @google/gemini-cli

# uv (Python fast package manager)
curl -Ls https://astral.sh/uv/install.sh | bash

# GUI tools
sudo pacman -S --needed --noconfirm \
  wofi waybar mako neovim  stow \
  bitwarden-cli wf-recorder slurp grim btop tree \
  hyprpaper hyprlock hypridle zsh gum

# VPN support
sudo pacman -S --needed --noconfirm openvpn networkmanager-openvpn

cd dotfiles
# Stow dotfiles
if [ ! -d "$HOME/.config" ]; then
  mkdir -p "$HOME/.config"
fi

stow -t "$HOME" --adopt --restow mako nvim waybar wofi mako kitty tmux zsh hyprland

git submodule update --init --recursive

# Create symlink for tmuxinator project template
mkdir -p ~/.config/tmuxinator/ && ln -sf /mnt/hdd1/Repos/i-use-arch-btw/dotfiles/tmux/.config/tmux/project_template.yml ~/.config/tmuxinator/project_template.ym


NEW_ZSH_FILE="$HOME/.config/zsh/zshrc"   

ZSH_FILE="$HOME/zshrc"

# if the new zsh file exists, delete the old one and only add a source that points to the new file
if [ -f "$NEW_ZSH_FILE" ]; then
  if [ -f "$ZSH_FILE" ]; then
    rm "$ZSH_FILE"
  fi
  echo "source $NEW_ZSH_FILE" > "$ZSH_FILE"
else
  echo "Warning: New Zsh file not found at $NEW_ZSH_FILE"
fi


echo "✅ Base setup complete. You may need to log out/in to apply Docker group changes."

