# Live-linked interactive zsh config (sourced from the home-manager-generated
# zshrc). Edits here take effect in new shells without a home-manager rebuild.

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# <C-l> accepts the whole zsh-autosuggestion (grayed-out preview);
# <C-j>/<C-k> mirror the down/up arrows (history-substring-search).
# zsh-vi-mode resets bindkeys on init, so (re)bind after it loads.
zvm_after_init_commands+=(
  'bindkey "^L" autosuggest-accept'
  'bindkey "^K" history-substring-search-up'
  'bindkey "^J" history-substring-search-down'
)
