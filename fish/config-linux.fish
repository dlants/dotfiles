set -gx SHELL (which fish)

if status is-interactive
    starship init fish | source
end

if test -f ~/.config/fish/secrets.fish
    source ~/.config/fish/secrets.fish
end

alias vi nvim
alias rm='rm -I'

# Enable vi keybindings
fish_vi_key_bindings

function git-clean-branches
    git branch --merged | grep -E -v "(^\*|master|main|dev)" | xargs git branch -d
end

function fish_title
    status current-command
end

# Linux-specific PATH
set -gx PATH $PATH $HOME/.local/bin

# Point `ty` (and other Python tooling) at the monolith's in-container venv so
# LSP-based type checking can resolve imports without committing repo config.
set -gx VIRTUAL_ENV /src/.venv
fish_add_path -g /src/.venv/bin
