# Clipboard Integration: Ghostty + Tmux + SSH + Neovim

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ macOS                                                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Ghostty Terminal                                          │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │ Tmux                                                │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │ SSH to remote                                 │  │  │  │
│  │  │  │  ┌─────────────────────────────────────────┐  │  │  │  │
│  │  │  │  │ Neovim                                  │  │  │  │  │
│  │  │  │  │                                         │  │  │  │  │
│  │  │  │  │  yank → OSC52 → ssh → tmux → ghostty   │  │  │  │  │
│  │  │  │  │                              ↓          │  │  │  │  │
│  │  │  │  │                         macOS clipboard │  │  │  │  │
│  │  │  │  └─────────────────────────────────────────┘  │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## How OSC52 Works

OSC52 is a terminal escape sequence that instructs the terminal to set the system clipboard:

```
ESC ] 52 ; c ; <base64-encoded-text> BEL
\033]52;c;dGVzdA==\007
```

When an application (like neovim) outputs this sequence:
1. It travels through SSH to the local machine
2. Tmux receives it and can either intercept or forward it
3. Ghostty receives it and sets the macOS clipboard

**Important limitation**: OSC52 paste (reading FROM clipboard) requires the terminal to respond back through the chain. This is unreliable over SSH and often blocked for security. Use `Cmd+V` instead.

## Tmux Configuration

### Critical Settings

```tmux
# Tell tmux that ghostty supports clipboard
set -ga terminal-features "xterm-ghostty:clipboard"

# Enable OSC52 handling - intercept AND forward to terminal
set -s set-clipboard on

# Allow escape sequences to pass through (needed for some apps)
set -g allow-passthrough on
```

### What `set-clipboard` Does

| Value      | Behavior |
|------------|----------|
| `off`      | Ignore OSC52 completely |
| `on`       | Intercept OSC52, store in tmux buffer, AND forward to terminal |
| `external` | Only forward to terminal, don't store in tmux buffer |

**Use `on`** - it works for both direct printf and neovim over SSH.

### `terminal-features` vs `terminal-overrides`

- `terminal-features "xterm-ghostty:clipboard"` - Tells tmux the terminal supports clipboard (tmux 3.2+)
- `terminal-overrides "...:Ms=..."` - Manually specifies the escape sequence format

**Use `terminal-features`** - it's cleaner and works better. Don't combine both as they can conflict.

### What NOT to use

```tmux
# DON'T use both of these together - they conflict:
set-option -ga terminal-overrides ",xterm-ghostty:Ms=\\E]52;c;%p2%s\\7"
set -ga terminal-features "xterm-ghostty:clipboard"

# DON'T use external if you need neovim clipboard over SSH:
set -s set-clipboard external
```

## Neovim Configuration

For remote Linux systems, configure OSC52 clipboard provider:

```lua
local is_linux = vim.loop.os_uname().sysname == "Linux"

if is_linux then
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
end
```

## What Works and What Doesn't

| Action | Works? | Notes |
|--------|--------|-------|
| printf OSC52 in tmux | ✅ | Direct clipboard write |
| printf OSC52 in tmux → ssh | ✅ | Passes through SSH |
| Yank in remote neovim → global clipboard | ✅ | OSC52 copy works |
| Cmd+V in remote neovim | ✅ | Terminal sends keystrokes |
| `p` in remote neovim from global clipboard | ❌ | OSC52 paste unreliable over SSH |

## Testing Procedure

### 1. Test OSC52 in Ghostty (outside tmux)

```bash
printf '\033]52;c;%s\007' "$(echo -n 'ghostty test' | base64)"
# Check clipboard - should contain "ghostty test"
```

### 2. Test OSC52 in Tmux

```bash
# Inside tmux
printf '\033]52;c;%s\007' "$(echo -n 'tmux test' | base64)"
# Check clipboard - should contain "tmux test"
```

### 3. Test OSC52 over SSH

```bash
# Inside tmux, SSH to remote
ssh remote
printf '\033]52;c;%s\007' "$(echo -n 'ssh test' | base64)"
# Check clipboard - should contain "ssh test"
```

### 4. Test Neovim Yank

```bash
# Inside tmux → ssh → neovim
# Yank some text with 'y'
# Check clipboard - should contain yanked text
```

### 5. Test Neovim Paste

```bash
# Copy something to clipboard on macOS
# In remote neovim, use Cmd+V (not 'p')
# Text should paste
```

## Debugging Commands

```bash
# Check tmux clipboard setting
tmux show-options -s set-clipboard

# Check terminal features
tmux show-options -s terminal-features

# Check if Ms capability is set
tmux info | grep Ms

# Check TERM variable
echo $TERM
```

## Troubleshooting

### OSC52 works in Ghostty but not in Tmux

Check `set-clipboard` is `on` and `terminal-features` includes clipboard.

### Neovim yank doesn't reach clipboard

1. Verify neovim is using OSC52: `:lua print(vim.inspect(vim.g.clipboard))`
2. Check `set-clipboard on` (not `external`)
3. Make sure `terminal-features "xterm-ghostty:clipboard"` is set

### printf works but neovim doesn't

Don't use `terminal-overrides` with `Ms` - use only `terminal-features clipboard`.

### Changes don't take effect after reload

Some settings (like `terminal-features`) require a **new tmux session**, not just config reload. Try `tmux kill-server` and restart.
