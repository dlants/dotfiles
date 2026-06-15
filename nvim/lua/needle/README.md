# needle

A fast, signal-aware fuzzy picker for neovim, rendered in plain splits (a prompt
window + a results window). It ranks files not just by fuzzy match score but by
weighted signals about how relevant a file is to what you're currently doing.

## Sources

| Command | Function | What it lists |
| --- | --- | --- |
| `:Needle [dir]` | `M.files(opts)` | files under the search root (fd/rg/find driven) |
| `:NeedleBuffers` | `M.buffers()` | the buffer list |
| `:NeedleHelp` | `M.help()` | help tags |

The search root is picked from the current buffer: cwd if the buffer is under
it, else the nearest git root, else the buffer's directory. `:Needle` accepts an
optional directory argument.

## Ranking signals

Files are scored by a fuzzy match (`needle/score.lua`) plus weighted signals,
shown as a `blamg` flag prefix column:

- **in buffer list**
- **adjacent dir** — directory proximity to open buffers (0..1)
- **recent access** — exponential decay against access half-life
- **recent mtime**
- **git dirty**

Access history is persisted to `stdpath("data")/needle/state.json` and updated
on `BufWinEnter` (throttled).

## Keymaps (inside the picker)

| Key | Action |
| --- | --- |
| `<C-j>` / `<C-n>` / `<Down>` | next result |
| `<C-k>` / `<C-p>` / `<Up>` | previous result |
| `<C-d>` / `<C-u>` | jump 10 down / up |
| `<CR>` | open |
| `<C-x>` | open in split |
| `<C-v>` | open in vsplit |
| `<C-t>` | open in tab |
| `<C-h>` | toggle unrestricted (`--no-ignore`) file listing |
| `<Esc>` / `<C-c>` | close |

## Setup

```lua
require("needle").setup({
  -- files_command = nil,        -- override: a list, or function(unrestricted) -> list
  weights = {
    in_buffer     = 60,
    adjacent_dir  = 50,
    recent_access = 50,
    recent_mtime  = 5,
    git_dirty     = 8,
  },
  access_half_life_s = 86400,    -- 1 day
  mtime_half_life_s  = 604800,   -- 1 week
  max_render         = 80,
  debounce_ms        = 25,
})
```

Suggested keymaps:

```lua
vim.keymap.set("n", "<leader>f", function() require("needle").files() end)
vim.keymap.set("n", "<leader>b", function() require("needle").buffers() end)
vim.keymap.set("n", "<leader>h", function() require("needle").help() end)
```
