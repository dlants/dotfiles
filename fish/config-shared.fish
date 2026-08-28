# Live-linked interactive fish config, sourced from the home-manager-generated
# config.fish (see programs.fish.interactiveShellInit in nix/common.nix) before
# the platform-specific file. Edits here take effect in new shells without a
# home-manager rebuild.

# Time fish waits for the rest of a multi-key sequence. The default of 30ms
# makes <Esc> feel sluggish.
set -g fish_escape_delay_ms 10

# Block cursor in normal mode, bar in insert. force_cursor is needed because
# fish can't detect cursor-shape support through tmux.
set -g fish_vi_force_cursor 1
set -g fish_cursor_default block
set -g fish_cursor_insert line
set -g fish_cursor_replace_one underscore
set -g fish_cursor_visual block

# Report the running command (not the shell) as the terminal title, so tmux
# window names are useful.
function fish_title
    status current-command
end

alias vi nvim
alias rm='rm -I'

function git-clean-branches --description 'Delete local branches already merged into the default branch'
    set -l default_branch (git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    if test -z "$default_branch"
        set default_branch main
    end
    git branch --merged | grep -E -v "(^\*|master|main|dev|$default_branch)" | xargs -r git branch -d
end

# fish calls this after (re)loading a keymap, and it wipes every binding when it
# does, so all custom binds have to live here rather than at top level.
function fish_user_key_bindings
    bind -M insert ctrl-l accept-autosuggestion
    bind -M insert ctrl-k history-prefix-search-backward
    bind -M insert ctrl-j history-prefix-search-forward

    # tmux forwards C-h/j/k/l to interactive shell panes (see tmux.conf is_vim).
    # Mirror vim-tmux-navigator: in INSERT mode C-j/C-k/C-l drive history search
    # / autosuggestion accept (bound above); in NORMAL mode C-h/j/k/l switch
    # tmux panes (so Esc first to navigate away from the shell).
    if set -q TMUX
        bind -M default ctrl-h 'tmux select-pane -L'
        bind -M default ctrl-j 'tmux select-pane -D'
        bind -M default ctrl-k 'tmux select-pane -U'
        bind -M default ctrl-l 'tmux select-pane -R'
    end
end

# Setting the variable (rather than calling fish_vi_key_bindings directly) is
# what makes fish load the vi keymaps and then call fish_user_key_bindings.
set -g fish_key_bindings fish_vi_key_bindings

if test -f ~/.config/fish/secrets.fish
    source ~/.config/fish/secrets.fish
end
