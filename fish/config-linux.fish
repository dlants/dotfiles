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
    set -l default_branch (git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    if test -z "$default_branch"
        set default_branch main
    end
    git branch --merged | grep -E -v "(^\*|master|main|dev|$default_branch)" | xargs -r git branch -d
end

function fish_title
    status current-command
end

# Linux-specific PATH
set -gx PATH $PATH $HOME/.local/bin

