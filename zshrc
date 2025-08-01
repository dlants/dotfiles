# Custom terminal title management
if [[ "$TERM" == "xterm-ghostty" ]]; then
  # Function to set terminal title
  set_terminal_title() {
    # Build the display path without using ~ substitution
    if [[ "$PWD" == "$HOME"* ]]; then
      local suffix="${PWD#$HOME}"
      printf '\e]0;~%s\a' "$suffix"
    else
      printf '\e]0;%s\a' "$PWD"
    fi
  }

  # Function to set title when command is running
  set_command_title() {
    local cmd="$1"
    local cwd
    if [[ "$PWD" == "$HOME"* ]]; then
      cwd="~${PWD#$HOME}"
    else
      cwd="$PWD"
    fi
    printf '\e]0;%s - %s\a' "$cmd" "$cwd"
  }

  # Set title before each prompt
  precmd_functions+=(set_terminal_title)

  # Set title when command starts (optional)
  preexec() {
    set_command_title "$1"
  }
fi

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

# Source Prezto. (Disabled for Ghostty testing)
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

# Native zsh completions
autoload -Uz compinit && compinit

# AWS CLI completion (find the zsh completer)
if [ -f /usr/local/bin/aws_zsh_completer.sh ]; then
  source /usr/local/bin/aws_zsh_completer.sh
elif [ -f /opt/homebrew/bin/aws_zsh_completer.sh ]; then
  source /opt/homebrew/bin/aws_zsh_completer.sh
fi
# export PATH="/usr/local/opt/openssl@3/bin:$PATH"

# installing this through prezto does not work w/ alacritty!
# to make this line work, brew install zsh-syntax-highlighting
# source /Users/denislantsman/src/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Created by `pipx` on 2022-11-16 21:25:09
export PATH="$PATH:/Users/denislantsman/.local/bin"
# Terraform native completion (run: terraform -install-autocomplete)



# Simple fast git prompt (local changes only, no remote checks)
if [[ "$TERM" != "dumb" ]]; then
  # Function to get git branch with local status only
  git_branch() {
    local branch
    branch=$(git branch 2>/dev/null | grep '^\*' | colrm 1 2)

    if [[ -n "$branch" ]]; then
      local status_symbols=""

      # Quick check for any uncommitted changes
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        status_symbols="*"
      fi

      echo " (${branch}${status_symbols})"
    fi
  }

  # Set the prompt
  setopt PROMPT_SUBST
  PROMPT='%F{blue}%~%f%F{green}$(git_branch)%f
$ '
fi

alias git-clean-branches='git branch --merged | egrep -v "(^\*|master|main|dev)" | xargs git branch -d'

export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

# Added by Windsurf
export PATH="/Users/denislantsman/.codeium/windsurf/bin:$PATH"

# bun completions
# [ -s "/Users/denislantsman/.bun/_bun" ] && source "/Users/denislantsman/.bun/_bun"

# bun
# export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# autotools
export PATH="/opt/homebrew/opt/libtool/libexec/gnubin:$PATH"

# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/denislantsman/.lmstudio/bin"
