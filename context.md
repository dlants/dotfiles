# Neovim Configuration Guide

## Key Configuration Files

### `nvim/lua/config/pack.lua`

Manages plugin installation using native `vim.pack` (Neovim 0.12+). Defines the
list of remote plugins via `vim.pack.add()` and sets up `PackChanged` autocmds
(e.g. running `TSUpdate` for treesitter and `npm run build` for magenta).

- **Plugin Manager**: Native `vim.pack` — no third-party manager
- **magenta.nvim**: installed from GitHub on Linux, loaded from local `~/src/magenta.nvim` elsewhere
- **Custom commands**: `:PluginUpdate` (fetch + confirm updates) and `:PluginClean` (remove unused plugins)

### `nvim/lua/config/plugins.lua`

Configures the plugins added in `pack.lua`:

- **LSP Configuration**: Complete LSP setup for multiple languages (TypeScript, Rust, Lua, etc.)
- **File Navigation**: snacks.nvim and oil.nvim for files and navigation
- **Git Integration**: Gitsigns, fugitive, and related tools
- **Completion**: nvim-cmp with LSP integration
- **Themes**: alabaster.nvim and other colorscheme options
- **Treesitter**: Syntax highlighting and text objects

### `nvim/lua/config/magenta.lua`

Configures magenta.nvim with its provider profiles.

### Plugin Highlights

- **magenta.nvim**: AI assistant with multiple provider profiles (Claude, GPT, work-specific endpoints)
- **LSP**: Full language server support with proper keybindings
- **Oil.nvim**: File explorer integrated with Neovim buffers
- **Leap.nvim**: Quick navigation with 's' key for bidirectional jumping

### Custom Pickers: needle & shuck

Two homegrown pickers (in `nvim/lua/needle/` and `nvim/lua/shuck.lua`) have
replaced fzf-lua. Both render in plain neovim splits (prompt window + results
window), share `<C-j>/<C-k>` navigation and `<CR>`/`<C-x>`/`<C-v>`/`<C-t>` open
actions, and pick a search root from the current buffer (cwd if the buffer is
under it, else the nearest git root, else the buffer's dir).

**needle** (`nvim/lua/needle/init.lua`) — a signal-aware fuzzy file picker.
- Sources: files (`M.files`), buffers (`M.buffers`), and help tags (`M.help`),
  exposed as `:Needle [dir]`, `:NeedleBuffers`, `:NeedleHelp`.
- Files are ranked by a fuzzy match score (`needle/score.lua`) plus weighted
  signals: in buffer list, directory proximity to open buffers, recent access
  (decaying), recent mtime, and git-dirty. Signal flags show as a `blamg`
  prefix column.
- Access history is persisted to `stdpath("data")/needle/state.json`.
- `<C-h>` toggles unrestricted (`--no-ignore`) file listing.
- Keymaps: `<leader>f` files, `<leader>b` buffers, `<leader>h` help.

**shuck** (`nvim/lua/shuck.lua`) — a streamed shell-command picker (a
vim-grepper replacement), `:Shuck` / `<leader>g`.
- Runs an arbitrary shell command (default `rg -H --no-heading --vimgrep `) and
  streams stdout/stderr live into the results window.
- Per-directory command history is persisted under `stdpath("data")/shuck/`;
  `<Up>`/`<Down>` cycle prefix-matched history, `<C-r>` opens a history picker.
- `<C-CR>` runs the command, `q` sends results to the quickfix list.

## Nix / Home Manager Setup

This dotfiles repo is managed with [Home Manager](https://github.com/nix-community/home-manager)
via a flake (`flake.nix`). Two configurations are defined:

- **`macos`** — aarch64-darwin, user `denis.lantsman`, dotfiles at `~/src/dotfiles` (uses `nix/darwin.nix`)
- **`devcontainer`** — aarch64-linux, user `aurelia`, dotfiles at `~/src/dotfiles` (uses `nix/linux.nix`)

### File Layout

- `flake.nix` — defines `homeConfigurations` and the `mkHomeConfig` helper
- `nix/common.nix` — shared config: packages, git, fish, starship, neovim, and
  config symlinks. Configs are live-linked with `mkOutOfStoreSymlink` (edits in
  the repo take effect immediately, no rebuild needed for plain config changes).
- `nix/darwin.nix` — macOS extras (Homebrew casks, hammerspoon, zig)
- `nix/linux.nix` — devcontainer extras (pkgx, work-skills clone, fish login shell)
- `nix/magenta-skills.nix` — generates magenta skill symlinks into `~/.claude/skills`

### Notable details

- A nixpkgs overlay in `common.nix` overrides `tree-sitter` to v0.26.8 (nvim-treesitter
  main branch needs >= 0.26.1; nixpkgs ships 0.25.x).
- Activation scripts clone `magenta.nvim` into `~/src` and set up magenta skills.
- Flakes are enabled via `~/.config/nix/nix.conf`.

### Installation / Apply Commands

`home-manager` should be on PATH:

```sh
home-manager switch --flake .#macos          # or .#devcontainer
```

Update flake inputs (nixpkgs, home-manager) then rebuild:

```sh
nix flake update
home-manager switch --flake .#<config>
```

## Tmux Setup

### Architecture

Two separate tmux instances run in parallel, each in its own ghostty window:

1. **Local tmux** on the host machine (macOS): runs `ta` directly to manage local sessions
2. **Remote tmux** inside the dev container: SSH into dev, then run `ta` there (the container has its own copy of these dotfiles)

Each tmux instance is independent — sessions are not shared across hosts. The fzf session picker (`scripts/tmux-session-using-fzf`) lists sessions only from the current tmux instance.

### Session Switching

- `ctrl-b o` — Opens fzf picker to switch between any pane across all sessions in the current tmux
- `ta <path>` — Create/switch to a session for a directory
