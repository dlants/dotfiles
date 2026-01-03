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

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :

# Created by `pipx` on 2025-12-15 18:40:48
set PATH $PATH /Users/denis.lantsman/.local/bin

# set display to pass X session to ssh
set -x DISPLAY :0
