#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Customize to your needs...
alias vi='nvim'
alias vim='nvim'
export EDITOR='nvim'

# source ~/.tmuxinator_completions.zsh

export LOGAN_URL="http://localhost:5003"
export DUMMY_SENDMAIL='yes'

# add Yarn
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

# add android emulator
export ANDROID_SDK="$HOME/Library/Android/sdk"
export PATH="$ANDROID_SDK/emulator:$ANDROID_SDK/tools:$ANDROID_SDK/platform-tools:$PATH"
export PATH="/usr/local/opt/postgresql@12/bin:$PATH"

alias luamake=/Users/dlants/src/lua-language-server/3rd/luamake/luamake

alias timeout='gtimeout'

# export FIREBASE_AUTH="/Users/dlants/.firebase.auth"
export PATH="/usr/local/bin/aws_completer:$PATH"

autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit
complete -C '/usr/local/bin/aws_completer' aws
export PATH="/usr/local/opt/openssl@3/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="/usr/local/opt/openjdk/bin:$PATH"

# if we're not in tmux, enter a tmux session
if [ -z "$TMUX" ]
then
  ta
fi

# Created by `pipx` on 2022-08-09 17:54:32
export PATH="$PATH:/Users/dlants/.local/bin"
export PATH="/usr/local/opt/postgresql@12/bin:$PATH"

 export PATH="$(pyenv root)/shims:$(pyenv root)/bin:$PATH"
 eval "$(pyenv init --path)"
 eval "$(pyenv init -)"
#  eval "$(pyenv virtualenv-init -)"
