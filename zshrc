source ~/dotfiles/antigen/antigen.zsh

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle pip
antigen bundle command-not-found
antigen bundle vundle

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting

# Load the theme.
antigen theme agnoster

# Tell antigen that you're done.
antigen apply

# shared history between shells
setopt inc_append_history
setopt share_history

export EDITOR=vim

export LOGAN_URL='http://login.desmos.com'
alias logan_local='export LOGAN_URL="http://local.desmos.com:5003"'

alias gulpwhile='while true; do gulp; done'
alias des='nodemon ~/src/pillow/app.js'
alias desdev='nodev ~/src/pillow/app.js'
alias mpw='openssl rand -base64 12'
alias go='cd ~/src/ && cd '

alias vi='vim'

# make alt + arrow move by word
bindkey "^[^[[D" backward-word
bindkey "^[^[[C" forward-word
