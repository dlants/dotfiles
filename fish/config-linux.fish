# Linux devcontainer-specific fish config, sourced after fish/config-shared.fish.

# `dev` and other tooling shell out to $SHELL; make sure it points at fish even
# when the shell wasn't entered via a normal login (e.g. ssh RemoteCommand).
set -gx SHELL (command -v fish)

# mise: applies per-directory [env] (e.g. AURELIA_ROOT from mise.toml) on cd.
# Required for `dev` to treat git worktrees as the monolith root.
command -q mise; and mise activate fish | source

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
__auto_venv

set -gx PATH $PATH $HOME/.local/bin
