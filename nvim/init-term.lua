-- disable netrw at the very start of your init.lua (strongly advised)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

require "config.lazy"
require "dev"

vim.cmd "filetype plugin indent on"

-- Leader keys defined in main init.lua

vim.o.background = "dark"
vim.o.number = true
vim.o.clipboard = "unnamedplus"
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 0
vim.o.expandtab = true
vim.o.shell = "/opt/homebrew/bin/zsh"

vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.hlsearch = true

vim.wo.relativenumber = true
vim.wo.wrap = false
vim.wo.cursorline = true
vim.wo.cursorcolumn = true
vim.wo.colorcolumn = "120"

vim.cmd "autocmd BufWritePre * StripWhitespace"

-- panel nav
vim.api.nvim_set_keymap("n", "<C-h>", "<C-w>h", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-l>", "<C-w>l", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-k>", "<C-w>k", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-j>", "<C-w>j", { noremap = true })

-- replicate unimpaired bindings
vim.api.nvim_set_keymap("n", "[j", "<C-O>", { noremap = true })
vim.api.nvim_set_keymap("n", "]j", "<C-I>", { noremap = true })
vim.api.nvim_set_keymap("n", "[q", ":cp<CR>", { noremap = true })
vim.api.nvim_set_keymap("n", "]q", ":cn<CR>", { noremap = true })
vim.api.nvim_set_keymap("n", "[l", ":lp<CR>", { noremap = true })
vim.api.nvim_set_keymap("n", "]l", ":lne<CR>", { noremap = true })
vim.api.nvim_set_keymap("n", "[<space>", "O<Esc>j", { noremap = true })
vim.api.nvim_set_keymap("n", "]<space>", "o<Esc>k", { noremap = true })
vim.api.nvim_set_keymap("n", "[f", ":colder<CR>", { noremap = true })
vim.api.nvim_set_keymap("n", "]f", ":cnewer<CR>", { noremap = true })

vim.api.nvim_set_keymap("n", "<leader>=", ":resize +5<CR>", { noremap = true })
vim.api.nvim_set_keymap("n", "<leader>-", ":resize -5<CR>", { noremap = true })