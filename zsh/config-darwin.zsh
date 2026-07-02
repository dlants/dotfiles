if [ -f ~/.config/zsh/secrets.zsh ]; then
    source ~/.config/zsh/secrets.zsh
fi

alias vi=nvim
alias rm='rm -I'

git-clean-branches() {
    local default_branch
    default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    if [ -z "$default_branch" ]; then
        default_branch=main
    fi
    git branch --merged | grep -E -v "(^\*|master|main|dev|$default_branch)" | xargs -r git branch -d
}

# OrbStack integration
source ~/.orbstack/shell/init.zsh 2>/dev/null || true

# macOS-specific PATH
export PATH="$PATH:/Users/denis.lantsman/.local/bin"
export DISPLAY=:0
