# VSCode-Neovim Integration Guide

## How VSCode and Neovim Interact

The VSCode-Neovim extension provides true Neovim integration within Visual Studio Code. It uses:

- **Neovim as a backend**: For normal mode, visual mode, and command mode operations
- **VSCode's native features**: For insert mode, completion, and other editor features
- **VSCode commands**: Exposed through a Lua API for integration

This hybrid approach gives you the editing power of Vim with the IDE features of VSCode.

## Common Issues and Solutions

### Packer vs Lazy.nvim

The extension initially failed with an error about `packer_compiled.lua` because there was a leftover Packer configuration while the current setup uses Lazy.nvim. Removing the old `~/.config/nvim/plugin/packer_compiled.lua` file fixed this issue.

### Config Reloading

There are several ways to reload the configuration:

1. **Reload Window**: Use Command Palette (Ctrl+Shift+P) to run "Reload Window"
2. **Disable/Enable Extension**: In the Extensions panel, disable and then re-enable the extension
3. **Reload Config**: Use the `<leader>sv` mapping we added to reload just the Neovim config

## VSCode-Neovim API

The extension provides a Lua API for interacting with VSCode:

```lua
local vscode = require('vscode')
```

### Key Functions

- `vscode.action(name, opts)`: Asynchronously execute a VSCode command
- `vscode.call(name, opts, timeout)`: Synchronously execute a VSCode command
- `vscode.get_config(name)`: Get a VSCode setting
- `vscode.update_config(name, value, target)`: Update a VSCode setting

### Example Usage

```lua
-- Execute a VSCode command
vscode.action('workbench.action.quickOpen')

-- Format document
vscode.action('editor.action.formatDocument')

-- Go to definition
vscode.action('editor.action.revealDefinition')
```

## Customized Mappings

We added several helpful VSCode-specific mappings:

```lua
-- File navigation
vim.api.nvim_set_keymap("n", "gf", "<Cmd>lua require('vscode').action('workbench.action.quickOpen')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>f", "<Cmd>lua require('vscode').action('workbench.action.quickOpen')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>e", "<Cmd>lua require('vscode').action('workbench.action.toggleSidebarVisibility')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>b", "<Cmd>lua require('vscode').action('workbench.action.showAllEditors')<CR>", { noremap = true, silent = true })

-- Code actions
vim.api.nvim_set_keymap("n", "gr", "<Cmd>lua require('vscode').action('editor.action.goToReferences')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "gd", "<Cmd>lua require('vscode').action('editor.action.revealDefinition')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "K", "<Cmd>lua require('vscode').action('editor.action.showHover')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>`", "<Cmd>lua require('vscode').action('editor.action.formatDocument')<CR>", { noremap = true, silent = true })

-- Workspace management
vim.api.nvim_set_keymap("n", "Q", "<Cmd>lua require('vscode').action('workbench.action.closeEditorsInGroup')<CR>", { noremap = true, silent = true })
```

## VSCode Settings for Neovim Users

### Limiting Tabs Per Group

You can limit VSCode to only show one tab per editor group with these settings in `settings.json`:

```json
"workbench.editor.limit.enabled": true,
"workbench.editor.limit.value": 1,
"workbench.editor.limit.perEditorGroup": true
```

Alternatively, the "Single Editor Tabs" extension can be installed.

## Identifying Neovim Context in Config

In your `init.lua`, you can detect whether Neovim is running inside VSCode:

```lua
if vim.g.vscode then
  -- VSCode-specific settings
else
  -- Standard Neovim settings
end
```

## Key Configuration Files

### `nvim/lua/plugins/plugins.lua`
The main plugin configuration file that defines all installed plugins and their settings:

- **Plugin Manager**: Uses Lazy.nvim for plugin management
- **AI Integration**: Includes magenta.nvim for Claude/GPT integration with multiple profiles
- **LSP Configuration**: Complete LSP setup for multiple languages (TypeScript, Rust, Lua, etc.)
- **File Navigation**: FZF-lua for fast file searching and navigation
- **Git Integration**: Gitsigns, fugitive, and related tools
- **Completion**: nvim-cmp with LSP integration and Copilot support
- **Themes**: Multiple colorscheme options with Flow theme as default
- **Treesitter**: Syntax highlighting and text objects

### Plugin Highlights
- **magenta.nvim**: AI assistant with multiple provider profiles (Claude, GPT, work-specific endpoints)
- **FZF-lua**: Fast fuzzy finding for files, buffers, and live grep
- **LSP**: Full language server support with proper keybindings
- **Oil.nvim**: File explorer integrated with Neovim buffers
- **Leap.nvim**: Quick navigation with 's' key for bidirectional jumping

## Useful Resources

- [VSCode-Neovim GitHub Repository](https://github.com/vscode-neovim/vscode-neovim)
- [VSCode-Neovim API Documentation](https://github.com/vscode-neovim/vscode-neovim#%EF%B8%8F-api)
- [VSCode Command Identifier Reference](https://code.visualstudio.com/api/references/commands)
- [VSCode Keyboard Shortcuts Reference](https://code.visualstudio.com/docs/getstarted/keybindings)

## Tmux Setup

### Architecture

Tmux runs on the **host machine** (macOS), not inside remote dev containers. This provides:
- Persistent sessions that survive SSH disconnects
- Consistent keybindings and configuration across all projects
- Fast local pane switching

### Remote Dev Sessions

The `ta` script (`scripts/ta`) creates special sessions for remote development:

```bash
ta dev           # Creates session "dev/src" → SSH to dev:/src
ta dev:/infra    # Creates session "dev/infra" → SSH to dev:/infra
```

These sessions:
1. Store remote host/path info in tmux environment variables (`TA_REMOTE_HOST`, `TA_REMOTE_PATH`)
2. Set up an `after-new-window` hook so new windows automatically SSH to the same remote location
3. First window SSHs into the remote path on creation

### Title Propagation

For the fzf session switcher to show meaningful names (not just "ssh"):

1. **Fish shell** on the remote sets terminal title via `fish_title` function in `fish/config-linux.fish`:
   ```fish
   function fish_title
       status current-command
   end
   ```

2. **Tmux** is configured to allow title changes (`allow-rename on`, `automatic-rename on` in `tmux.conf`)

3. **fzf switcher** (`scripts/tmux-session-using-fzf`) uses `#{pane_title}` instead of `#{pane_current_command}` to display the propagated title

This chain allows you to see the actual command running on the remote (e.g., "nvim", "cargo build") instead of just "ssh" in the session picker.

### Session Switching

- `ctrl-b o` — Opens fzf picker to switch between any pane across all sessions
- `ta <path>` — Create/switch to a session for a local directory
- `ta dev` — Create/switch to a remote dev session

## Tips for Effective Use

1. Use VSCode's native features for insert mode, intellisense, and UI operations
2. Use Neovim for text navigation, manipulation, and command-mode operations
3. Limit the plugins you load in VSCode to avoid conflicts (see [Troubleshooting](https://github.com/vscode-neovim/vscode-neovim#troubleshooting))
4. For optimal performance, disable neovim plugins that provide features already available in VSCode