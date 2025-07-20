# shared config
if [[ -s "${ZDOTDIR:-$HOME}/.zshsecret" ]]; then
  source "${ZDOTDIR:-$HOME}/.zshsecret"
fi

alias vi='nvim'
alias vim='nvim'
export EDITOR='nvim'

# work stuff
export DUMMY_SENDMAIL='yes'
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH=`which chromium`

if [[ "$TERM_PROGRAM" = "zed" ]]; then
  # Zed specific config
  bindkey "^?" backward-delete-char
  bindkey "^[[A" history-beginning-search-backward
else
  # Source Prezto.
  if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
    source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
  fi

#   # add android emulator
#   export ANDROID_SDK="$HOME/Library/Android/sdk"
#   export PATH="$ANDROID_SDK/emulator:$ANDROID_SDK/tools:$ANDROID_SDK/platform-tools:$PATH"
#   export PATH="/usr/local/opt/postgresql@12/bin:$PATH"
#
#   alias luamake=/Users/dlants/src/lua-language-server/3rd/luamake/luamake
#
  alias timeout='gtimeout'
#
  export PATH="/usr/local/bin/aws_completer:$PATH"

  autoload bashcompinit && bashcompinit
  autoload -Uz compinit && compinit
  complete -C '/usr/local/bin/aws_completer' aws
  export PATH="/usr/local/opt/openssl@3/bin:$PATH"

  # installing this through prezto does not work w/ alacritty!
  # to make this line work, brew install zsh-syntax-highlighting
  source /Users/denislantsman/src/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

  # Created by `pipx` on 2022-11-16 21:25:09
  export PATH="$PATH:/Users/denislantsman/.local/bin"
  autoload -U +X bashcompinit && bashcompinit
  complete -o nospace -C /opt/homebrew/Cellar/tfenv/3.0.0/versions/1.2.9/terraform terraform
  alias git-clean-branches='git branch --merged | egrep -v "(^\*|master|main|dev)" | xargs git branch -d'

  export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
fi

# Added by Windsurf
export PATH="/Users/denislantsman/.codeium/windsurf/bin:$PATH"

# bun completions
[ -s "/Users/denislantsman/.bun/_bun" ] && source "/Users/denislantsman/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# autotools
export PATH="/opt/homebrew/opt/libtool/libexec/gnubin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/denislantsman/.lmstudio/bin"
