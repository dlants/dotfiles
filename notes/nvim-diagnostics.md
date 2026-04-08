# Neovim Diagnostics Navigation

How to find and navigate errors, warnings, and other LSP diagnostics (TypeScript errors, unused variable warnings, etc.) in Neovim.

## Current Keybindings

All diagnostic keybindings are defined in `nvim/lua/plugins/plugins.lua` inside the LSP `on_attach` function. They are only active in buffers with an attached language server.

### Viewing Diagnostics

| Keymap | Action | Notes |
|--------|--------|-------|
| `<leader>e` | Show virtual lines for diagnostics at cursor | Disappears on next cursor move |
| `gl` | Open diagnostic float at cursor | Readable popup with full error message |
| `<leader>d` | Send all diagnostics to quickfix list | See all errors/warnings in one list |
| `<leader>D` | Fuzzy-search document diagnostics (fzf-lua) | Filter/search through current file diagnostics |
| `<leader>W` | Fuzzy-search workspace diagnostics (fzf-lua) | Filter/search across all open project files |

### Jumping Between Diagnostics

| Keymap | Action |
|--------|--------|
| `]d` | Jump to next diagnostic |
| `[d` | Jump to previous diagnostic |

Both show virtual lines temporarily after jumping.

### Acting on Diagnostics

| Keymap | Action |
|--------|--------|
| `<leader>x` | Open code actions (fzf-lua picker) — quick fixes, auto-imports, etc. |

### Quickfix Navigation (after `<leader>d`)

| Keymap | Action |
|--------|--------|
| `]q` | Next quickfix item |
| `[q` | Previous quickfix item |

## Diagnostic Display Settings

Configured in `vim.diagnostic.config()`:

- **virtual_text**: Off (no inline text after lines)
- **virtual_lines**: Off by default, shown temporarily on `]d`/`[d`/`<leader>e`
- **signs**: On (gutter icons)
- **underline**: On (squiggly underlines on errors)
- **severity_sort**: On (errors shown before warnings)

## Statusline

Diagnostic counts are shown in lualine (bottom status bar) via the `nvim_lsp` source.

## Workflow Tips

1. **Quick check**: Press `<leader>e` or `gl` to see the error under the cursor
2. **Fix one by one**: Use `]d` / `[d` to hop through errors, `<leader>x` to apply fixes
3. **See everything**: `<leader>d` to populate quickfix, then `]q`/`[q` to navigate
4. **Search for specific error**: `<leader>D` to fuzzy-search diagnostics by message text
5. **Workspace-wide**: `<leader>W` to see all diagnostics across the project
