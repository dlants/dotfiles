-- disable netrw at the very start of your init.lua (strongly advised)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

require "plugins"

vim.cmd "colorscheme OceanicNext"
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
vim.o.shell = "/opt/homebrew/bin/zsh"

vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.hlsearch = true

vim.wo.wrap = false
vim.wo.cursorline = true
vim.wo.cursorcolumn = true
vim.wo.colorcolumn = "120"

vim.cmd "autocmd BufWritePre * StripWhitespace"

-- replace unimpaired bindings
vim.api.nvim_set_keymap("n", "[j", "<C-O>", {noremap = true})
vim.api.nvim_set_keymap("n", "]j", "<C-I>", {noremap = true})
vim.api.nvim_set_keymap("n", "[q", ":cp<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "]q", ":cn<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "[l", ":lp<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "]l", ":lne<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "[<space>", "O<Esc>j", {noremap = true})
vim.api.nvim_set_keymap("n", "]<space>", "o<Esc>k", {noremap = true})
vim.api.nvim_set_keymap("n", "[f", ":colder<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "]f", ":cnewer<CR>", {noremap = true})


vim.api.nvim_set_keymap("n", "<leader>=", ":resize +5<CR>", {noremap = true})
vim.api.nvim_set_keymap("n", "<leader>-", ":resize -5<CR>", {noremap = true})

require "config/hop"
require "config/lsp"
require "config/completion-and-snippets"
require "config/lualine"
require "config/formatter"
require "config/treesitter"
require "config/harpoon"
-- require "config/trouble"
-- require "config/lua-dev"
-- require "config/telescope"
require "config/terraform"
require "config/nvimtree"

-- fzf
-- vim.cmd "set rtp+=/opt/homebrew/opt/fzf"
-- vim.cmd "let g:fzf_layout = {'up': '~50%'}"
-- vim.api.nvim_set_keymap("n", "<leader>p", ":GFiles<CR>", {noremap = true, silent = true})
-- vim.api.nvim_set_keymap("n", "<leader>o", ":Files<CR>", {noremap = true, silent = true})

-- fzf-lua
vim.keymap.set("n", "<leader>p", "<cmd>lua require('fzf-lua').git_files()<CR>", { silent = true })
vim.keymap.set("n", "<leader>o", "<cmd>lua require('fzf-lua').files()<CR>", { silent = true })

-- grepper
vim.cmd "runtime plugin/grepper.vim"
vim.cmd "let g:grepper.prompt_quote = 0"
vim.cmd "let g:grepper.tools = ['rg']"
-- vim.cmd "let g:grepper.rg.grepprg .= ' --hidden'"
vim.api.nvim_set_keymap("n", "<leader>g", ":Grepper<CR>", {noremap = true, silent = true})

-- vim.cmd "augroup lsp"
-- vim.cmd "  au!"
-- vim.cmd "  au FileType java lua print('hello'); require('config/lsp').start_jdt()"
-- vim.cmd "augroup end"
