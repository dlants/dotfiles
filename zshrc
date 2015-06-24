setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done

# shared history between shells
setopt inc_append_history
setopt share_history

export EDITOR=vim

alias mpw='openssl rand -base64 12'
alias vi='vim'

# make alt + arrow move by word
bindkey "^[^[[D" backward-word
bindkey "^[^[[C" forward-word
