export SHELL="$(command -v zsh)"

if command -v mise > /dev/null; then
    # mise: applies per-directory [env] (e.g. AURELIA_ROOT from mise.toml) on cd.
    # Required for `dev` to treat git worktrees as the monolith root.
    eval "$(mise activate zsh)"
fi

# Auto-activate the nearest .venv when in a project dir or subdir, and deactivate
# when leaving. Walks up from $PWD looking for a `.venv/`. This is independent of
# mise (the aurelia mise.toml disables the python tool / pyenv manages interpreters),
# so each git worktree's local .venv puts its binaries (python, ty, pytest, ...) on PATH.
__auto_venv() {
    local dir="$PWD" found=""
    while [ -n "$dir" ]; do
        if [ -d "$dir/.venv" ]; then
            found="$dir/.venv"
            break
        fi
        [ "$dir" = "/" ] && break
        dir="$(dirname "$dir")"
    done

    [ "$found" = "$__AUTO_VENV" ] && return

    if [ -n "$__AUTO_VENV" ]; then
        export PATH="${PATH//$__AUTO_VENV\/bin:/}"
        unset VIRTUAL_ENV
        unset __AUTO_VENV
    fi

    if [ -n "$found" ]; then
        export VIRTUAL_ENV="$found"
        export PATH="$found/bin:$PATH"
        export __AUTO_VENV="$found"
    fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd __auto_venv
__auto_venv

if [ -f ~/.config/zsh/secrets.zsh ]; then
    source ~/.config/zsh/secrets.zsh
fi

alias ls='ls --color=auto'
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

# Linux-specific PATH
export PATH="$PATH:$HOME/.local/bin"
