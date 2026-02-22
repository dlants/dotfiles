if status is-interactive
    starship init fish | source
end

# Add Nix paths manually (pure fish, no bass needed)
if test -d ~/.nix-profile/bin
    set -gx PATH ~/.nix-profile/bin $PATH
end
if test -d /nix/var/nix/profiles/default/bin
    set -gx PATH /nix/var/nix/profiles/default/bin $PATH
end

# Add Homebrew to PATH (for GUI apps like Ghostty)
if test -d /opt/homebrew/bin
    set -gx PATH /opt/homebrew/bin $PATH
end

if test -f ~/.config/fish/secrets.fish
    source ~/.config/fish/secrets.fish
end

alias vi nvim
alias rm='rm -I'

# Enable vi keybindings
fish_vi_key_bindings

function git-clean-branches
    git branch --merged | grep -E -v "(^\*|master|main|dev)" | xargs git branch -d
end

function fish_title
    status current-command
end

# OrbStack integration
source ~/.orbstack/shell/init2.fish 2>/dev/null || true

# macOS-specific PATH
set -gx PATH $PATH /Users/mugabo/.local/bin
set -gx DISPLAY :0
