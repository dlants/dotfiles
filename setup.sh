#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect platform
if [[ "$(uname)" == "Darwin" ]]; then
    PROFILE="macos"
elif [[ "$(uname)" == "Linux" ]]; then
    PROFILE="devcontainer"
else
    echo "Unsupported platform: $(uname)"
    exit 1
fi

echo "==> Setting up for profile: $PROFILE"

# Install Nix if not present
if ! command -v nix &> /dev/null; then
    echo "==> Installing Nix..."
    sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install)

    # Source nix in current shell
    if [[ -f ~/.nix-profile/etc/profile.d/nix.sh ]]; then
        source ~/.nix-profile/etc/profile.d/nix.sh
    elif [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
else
    echo "==> Nix already installed"
fi

# Enable flakes if not already configured
if ! grep -q "experimental-features" ~/.config/nix/nix.conf 2>/dev/null; then
    echo "==> Enabling flakes..."
    # Remove broken symlinks (e.g. from a previous home-manager generation whose nix store was wiped)
    [[ -L ~/.config/nix/nix.conf && ! -e ~/.config/nix/nix.conf ]] && rm ~/.config/nix/nix.conf
    [[ -L ~/.config/nix && ! -e ~/.config/nix ]] && rm ~/.config/nix
    mkdir -p ~/.config/nix
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
fi

# Run home-manager
echo "==> Running home-manager..."
nix run home-manager/master -- switch --flake "$DOTFILES_DIR#$PROFILE" -b backup

echo "==> Done! Open a new terminal to use your new shell."
