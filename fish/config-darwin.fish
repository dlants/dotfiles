# macOS-specific fish config, sourced after fish/config-shared.fish.

# OrbStack integration
test -f ~/.orbstack/shell/init2.fish; and source ~/.orbstack/shell/init2.fish

set -gx PATH $PATH /Users/denis.lantsman/.local/bin
set -gx DISPLAY :0
