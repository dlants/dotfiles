#! /bin/bash
ln -sf ~/src/dotfiles/tmux.conf ~/.tmux.conf
ln -sf ~/src/dotfiles/zshrc ~/.zshrc
ln -sf ~/src/dotfiles/zpreztorc ~/.zpreztorc
ln -sf ~/src/dotfiles/nvim/init.lua ~/.config/nvim/init.lua
ln -sf ~/src/dotfiles/nvim/lua ~/.config/nvim/lua

ln -sf ~/src/dotfiles/scripts/start-tmux /usr/local/bin/start-tmux
ln -sf ~/src/dotfiles/scripts/tmux-session-using-fzf /usr/local/bin/tmux-session-using-fzf
ln -sf ~/src/dotfiles/scripts/ta /usr/local/bin/ta
