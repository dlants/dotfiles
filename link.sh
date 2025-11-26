#! /bin/bash
set -euxo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ln -sf "$DOTFILES_DIR/tmux.conf" ~/.tmux.conf
ln -sf "$DOTFILES_DIR/zshrc" ~/.zshrc
ln -sf "$DOTFILES_DIR/digrc" ~/.digrc
ln -sf "$DOTFILES_DIR/zpreztorc" ~/.zpreztorc
ln -sf "$DOTFILES_DIR/nvim/init.lua" ~/.config/nvim/init.lua
ln -sf "$DOTFILES_DIR/nvim/lua" ~/.config/nvim/lua

# mkdir -p ~/.config/helix
# ln -sf "$DOTFILES_DIR/helix.yml" ~/.config/helix/config.toml

mkdir -p ~/.config/ghostty
ln -sf "$DOTFILES_DIR/ghostty/config" ~/.config/ghostty/config
ln -sf "$DOTFILES_DIR/ghostty/themes" ~/.config/ghostty/themes
ln -sf "$DOTFILES_DIR/ghostty/shaders" ~/.config/ghostty/shaders

ln -sf "$DOTFILES_DIR/hammerspoon" ~/.hammerspoon

# ln -sf "$DOTFILES_DIR/scripts/start-tmux" /usr/local/bin/start-tmux
# ln -sf "$DOTFILES_DIR/scripts/tmux-session-using-fzf" /usr/local/bin/tmux-session-using-fzf
# ln -sf "$DOTFILES_DIR/scripts/ta" /usr/local/bin/ta

mkdir -p ~/.magenta
ln -sf "$DOTFILES_DIR/magenta-skills" ~/.magenta/skills
