require "plugins"

vim.cmd "colorscheme jellybeans"
vim.cmd "filetype plugin indent on"

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.o.background = "dark"
vim.o.number = true
vim.o.clipboard = "unnamedplus"
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 0
vim.o.expandtab = true
vim.o.shell = "/usr/local/bin/zsh"

vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.hlsearch = true

vim.wo.wrap = false
vim.wo.cursorline = true
vim.wo.cursorcolumn = true
vim.wo.colorcolumn = "120"

vim.cmd "autocmd BufWritePre * StripWhitespace"

vim.api.nvim_set_keymap("n", "[j", "<C-O>", {noremap = true})
vim.api.nvim_set_keymap("n", "]j", "<C-I>", {noremap = true})

vim.api.nvim_set_keymap("n", "<leader>=", ":resize +5<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "<leader>-", ":resize -5<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "<leader>+", ":vertical resize +5<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "<leader>_", ":vertical resize -5<CR>", {noremap = true})

require "config/hop"
require "config/lsp"
require "config/compe"
require "config/lualine"
require "config/formatter"
require "config/treesitter"

-- fzf
vim.cmd "set rtp+=/usr/local/opt/fzf"
vim.cmd "let g:fzf_layout = {'up': '~50%'}"
vim.api.nvim_set_keymap("n", "<leader>p", ":GFiles<CR>", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<leader>o", ":Files<CR>", {noremap = true, silent = true})

-- grepper
vim.cmd "runtime plugin/grepper.vim"
vim.cmd "let g:grepper.prompt_quote = 0"
vim.cmd "let g:grepper.tools = ['rg']"
vim.api.nvim_set_keymap("n", "<leader>g", ":Grepper<CR>", {noremap = true, silent = true})
