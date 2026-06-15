# shuck

A streamed shell-command picker for neovim (a vim-grepper / live-grep
replacement), rendered in plain splits (a prompt window + a results window). You
edit an arbitrary shell command in the prompt; its stdout/stderr stream live
into the results window as it runs.

## Opening

```vim
:Shuck
```

The default command is `rg -H --no-heading --vimgrep ` — type your pattern after
it and run. The search root is picked from the current buffer (cwd if the buffer
is under it, else the nearest git root, else the buffer's directory).

Per-directory command history is persisted under `stdpath("data")/shuck/`.

## Keymaps (inside the picker)

| Key | Action |
| --- | --- |
| `<C-CR>` | run the command in the prompt |
| `<CR>` | open the selected result |
| `<C-x>` / `<C-v>` / `<C-t>` | open in split / vsplit / tab |
| `<C-j>` / `<C-k>` | next / previous result |
| `<C-d>` / `<C-u>` | jump 10 down / up |
| `<Up>` / `<Down>` | cycle prefix-matched command history |
| `<C-r>` | open the history picker |
| `q` | send results to the quickfix list |
| `<Esc>` / `<C-c>` | close |

## Setup

```lua
require("shuck").setup({
  default_cmd     = "rg -H --no-heading --vimgrep ",
  max_render      = 200,
  max_results     = 10000,
})
```

Suggested keymap:

```lua
vim.keymap.set("n", "<leader>g", function() require("shuck").toggle({}) end)
```
