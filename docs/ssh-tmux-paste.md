# OSC52 Clipboard Through SSH and Tmux

## The Problem

Yanking in neovim doesn't populate the system clipboard when running:
```
ghostty (local) → tmux (local) → ssh → neovim (remote)
```

But it works fine with:
```
ghostty (local) → ssh → neovim (remote)
```

## How OSC52 Works

OSC52 is a terminal escape sequence that tells the terminal to set the system clipboard:
```
ESC ] 52 ; c ; <base64-encoded-text> BEL
```

Neovim on the remote sends this sequence, and it needs to travel through SSH and tmux to reach ghostty, which then sets the macOS clipboard.

## Tmux Configuration Required

### 1. allow-passthrough

Allows escape sequences from applications to pass through to the outer terminal:
```
set -g allow-passthrough on
```

### 2. set-clipboard

Controls how tmux handles OSC52 sequences:
- `on` — accept OSC52 to create tmux buffer AND forward to terminal clipboard
- `external` — forward to terminal clipboard but DON'T store in tmux buffer
- `off` — ignore completely

```
set -s set-clipboard on
```

**Important:** tmux only forwards OSC52 if the terminfo has an `Ms` entry (clipboard capability).

### 3. terminal-overrides for Ms capability

The `xterm-ghostty` terminfo doesn't include the `Ms` capability by default. Add it manually:
```
set-option -ga terminal-overrides ",xterm-ghostty:Ms=\\E]52;c;%p2%s\\7"
```

### 4. terminal-features (optional)

Tell tmux that ghostty supports clipboard:
```
set -ga terminal-features "xterm-ghostty:clipboard"
```

## Testing OSC52 Directly

To test if OSC52 is working without neovim:
```bash
printf '\033]52;c;%s\007' "$(echo -n 'test clipboard' | base64)"
```

Then check if "test clipboard" is in your system clipboard.

## Neovim Configuration

In `init.lua`, for Linux/remote systems, configure the OSC52 clipboard provider:
```lua
vim.o.clipboard = 'unnamedplus'
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
    ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
  },
}
```

**Note:** OSC52 paste (reading from clipboard) requires the terminal to respond, which often doesn't work through SSH/tmux. Copying (writing to clipboard) is more reliable.

## Remote Dev Container Setup

The dev container installs the ghostty terminfo so the remote understands `xterm-ghostty`:

```sh
#!/bin/sh
# Sets up Ghostty terminal definition on the remote machine
# to fix the "broken backspace" issue.

TERMINFO_FILE="$HOME/dev-in-docker-shared-files/ghostty.terminfo"

if [ -f "$TERMINFO_FILE" ]; then
    tic -x "$TERMINFO_FILE"
else
    echo "Warning: $TERMINFO_FILE not found. Ghostty terminal definition not installed."
fi
```

This was originally set up expecting `ghostty → ssh → neovim` (no tmux). When tmux is in the chain, both:
1. The **local** tmux needs to know ghostty supports OSC52 (via `Ms` in terminal-overrides)
2. The **remote** needs the terminfo so it understands the TERM=xterm-ghostty that gets passed through SSH

## Troubleshooting

1. **Check tmux settings:**
   ```bash
   tmux show-options -wg allow-passthrough
   tmux show-options -s set-clipboard
   tmux show-options -s terminal-features
   ```

2. **Check terminfo for Ms capability:**
   ```bash
   infocmp xterm-ghostty | grep Ms
   ```

3. **After changing terminal-overrides**, you need to start a **new tmux session** (not just reload config) because they're evaluated at session creation.
