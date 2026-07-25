# Live-linked interactive zsh config (sourced from the home-manager-generated
# zshrc, after all plugins). Edits here take effect in new shells without a
# home-manager rebuild.
#
# vi mode is zsh's native one (`bindkey -v` via programs.zsh.defaultKeymap),
# not the zsh-vi-mode plugin. The pieces that plugin provided are assembled
# below out of functions that ship with zsh, at ~0ms instead of ~40ms.

# Time (in 1/100s) zsh waits for the rest of a multi-key sequence. The default
# of 40 makes <Esc> feel sluggish; 10 is responsive without breaking arrow keys.
KEYTIMEOUT=10

# Text objects: ci"/da'/ci(/da[ etc. select-bracketed and select-quoted ship
# with zsh and cover what zsh-vi-mode's text objects did.
autoload -Uz select-bracketed select-quoted
zle -N select-bracketed
zle -N select-quoted
for m in visual viopp; do
  for c in {a,i}${(s..)^:-\'\"\`\|,./:;=+@}; do
    bindkey -M $m $c select-quoted
  done
  for c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
    bindkey -M $m $c select-bracketed
  done
done
unset m c

# Surround: ds/cs/ys, same bindings vim-surround uses.
autoload -Uz surround
zle -N delete-surround surround
zle -N add-surround surround
zle -N change-surround surround
bindkey -M vicmd cs change-surround
bindkey -M vicmd ds delete-surround
bindkey -M vicmd ys add-surround
bindkey -M visual S add-surround

# Cursor shape follows the mode (block in normal, bar in insert), and reset to
# a bar before running a command so the cursor isn't a block during output.
_vi_cursor_shape() { printf '\e[%s q' "$1" }
zle-keymap-select() {
  if [[ $KEYMAP == vicmd ]]; then _vi_cursor_shape 2; else _vi_cursor_shape 6; fi
}
zle -N zle-keymap-select
zle-line-init() { _vi_cursor_shape 6 }
zle -N zle-line-init
autoload -Uz add-zsh-hook
add-zsh-hook preexec '_vi_cursor_shape 6'

bindkey -M viins '^[[A' history-substring-search-up
bindkey -M viins '^[[B' history-substring-search-down
bindkey -M viins '^L' autosuggest-accept
bindkey -M viins '^K' history-substring-search-up
bindkey -M viins '^J' history-substring-search-down

# fzf's zsh integration binds "^I" to fzf-completion; we want fzf-tab instead.
bindkey '^I' fzf-tab-complete
bindkey -M viins '^I' fzf-tab-complete

# tmux forwards C-h/j/k/l to interactive zsh panes (see tmux.conf is_vim, which
# also matches zsh). We mirror vim-tmux-navigator: in INSERT mode C-j/C-k/C-l
# drive history-search / autosuggestion accept (bound above); in NORMAL (vicmd)
# mode C-h/j/k/l switch tmux panes (Esc first to navigate away from the shell).
if [[ -n $TMUX ]]; then
  _zsh_tmux_pane_left()  { tmux select-pane -L }
  _zsh_tmux_pane_down()  { tmux select-pane -D }
  _zsh_tmux_pane_up()    { tmux select-pane -U }
  _zsh_tmux_pane_right() { tmux select-pane -R }
  zle -N _zsh_tmux_pane_left
  zle -N _zsh_tmux_pane_down
  zle -N _zsh_tmux_pane_up
  zle -N _zsh_tmux_pane_right
  bindkey -M vicmd '^H' _zsh_tmux_pane_left
  bindkey -M vicmd '^J' _zsh_tmux_pane_down
  bindkey -M vicmd '^K' _zsh_tmux_pane_up
  bindkey -M vicmd '^L' _zsh_tmux_pane_right
fi
