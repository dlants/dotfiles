# Live-linked interactive zsh config (sourced from the home-manager-generated
# zshrc). Edits here take effect in new shells without a home-manager rebuild.

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# tmux forwards C-h/j/k/l to interactive zsh panes (see tmux.conf is_vim, which
# also matches zsh). We mirror vim-tmux-navigator: in INSERT mode C-j/C-k/C-l
# drive history-search / autosuggestion accept; in NORMAL (vicmd) mode
# C-h/j/k/l switch tmux panes (Esc first to navigate away from the shell).
if [[ -n $TMUX ]]; then
  _zsh_tmux_pane_left()  { tmux select-pane -L }
  _zsh_tmux_pane_down()  { tmux select-pane -D }
  _zsh_tmux_pane_up()    { tmux select-pane -U }
  _zsh_tmux_pane_right() { tmux select-pane -R }
  zle -N _zsh_tmux_pane_left
  zle -N _zsh_tmux_pane_down
  zle -N _zsh_tmux_pane_up
  zle -N _zsh_tmux_pane_right
fi

# zsh-vi-mode resets bindkeys on init, so (re)bind after it loads.
zvm_after_init_commands+=(
  'bindkey -M viins "^L" autosuggest-accept'
  'bindkey -M viins "^K" history-substring-search-up'
  'bindkey -M viins "^J" history-substring-search-down'
)
if [[ -n $TMUX ]]; then
  zvm_after_init_commands+=(
    'bindkey -M vicmd "^H" _zsh_tmux_pane_left'
    'bindkey -M vicmd "^J" _zsh_tmux_pane_down'
    'bindkey -M vicmd "^K" _zsh_tmux_pane_up'
    'bindkey -M vicmd "^L" _zsh_tmux_pane_right'
  )
fi
