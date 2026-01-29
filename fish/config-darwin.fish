if status is-interactive
    # Commands to run in interactive sessions can go here
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

# OrbStack integration
source ~/.orbstack/shell/init2.fish 2>/dev/null || true

# macOS-specific PATH
set -gx PATH $PATH /Users/denis.lantsman/.local/bin
set -gx DISPLAY :0
