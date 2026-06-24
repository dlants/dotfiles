set -gx SHELL (which fish)

if status is-interactive
    starship init fish | source
    # mise: applies per-directory [env] (e.g. AURELIA_ROOT from mise.toml) on cd.
    # Required for `dev` to treat git worktrees as the monolith root.
    command -q mise; and mise activate fish | source
end

# Auto-activate the nearest .venv when in a project dir or subdir, and deactivate
# when leaving. Walks up from $PWD looking for a `.venv/`. This is independent of
# mise (the aurelia mise.toml disables the python tool / pyenv manages interpreters),
# so each git worktree's local .venv puts its binaries (python, ty, pytest, ...) on PATH.
function __auto_venv --on-variable PWD --description 'Activate nearest .venv on cd'
    set -l dir $PWD
    set -l found ""
    while test -n "$dir"
        if test -d "$dir/.venv"
            set found "$dir/.venv"
            break
        end
        test "$dir" = "/"; and break
        set dir (path dirname $dir)
    end

    test "$found" = "$__AUTO_VENV"; and return

    if set -q __AUTO_VENV; and test -n "$__AUTO_VENV"
        set -gx PATH (string match -v "$__AUTO_VENV/bin" $PATH)
        set -e VIRTUAL_ENV
        set -e __AUTO_VENV
    end

    if test -n "$found"
        set -gx VIRTUAL_ENV "$found"
        set -gx PATH "$found/bin" $PATH
        set -gx __AUTO_VENV "$found"
    end
end

if status is-interactive
    __auto_venv
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

