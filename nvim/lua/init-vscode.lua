require "plugins-vscode"

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

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

-- replace unimpaired bindings
local opts = {noremap = true}
vim.keymap.set("n", "[j", ":call VSCodeNotify('workbench.action.navigateBack')<CR>", opts)
vim.keymap.set("n", "]j", ":call VSCodeNotify('workbench.action.navigateForward')<CR>", opts)
vim.keymap.set("n", "[<space>", "O<Esc>j", opts)
vim.keymap.set("n", "]<space>", "o<Esc>k", opts)
vim.keymap.set("n", "]e", ":call VSCodeNotify('editor.action.marker.next')<CR>")
vim.keymap.set("n", "[e", ":call VSCodeNotify('editor.action.marker.prev')<CR>")

vim.keymap.set("n", "<leader>d", ":call VSCodeNotify('editor.action.revealDefinition')<CR>")
vim.keymap.set("n", "<leader>r", ":call VSCodeNotify('editor.action.referenceSearch.trigger')<CR>")
vim.keymap.set("n", "<leader>R", ":call VSCodeNotify('editor.action.rename')<CR>")
vim.keymap.set("n", "<leader>t", ":call VSCodeNotify('editor.action.showDefinitionPreviewHover')<CR>")
vim.keymap.set("n", "<leader>o", ":call VSCodeNotify('workbench.action.quickOpen')<CR>")
vim.keymap.set("n", "<leader>p", ":call VSCodeNotify('workbench.action.quickOpen')<CR>")
vim.keymap.set("n", "<c-w>x", ":call VSCodeNotify('workbench.action.closeEditorsInGroup')<CR>")

vim.keymap.set("n", "<leader>s", ":call VSCodeNotify('workbench.scm.focus')<CR>")
vim.keymap.set("n", "<leader>g", ":call VSCodeNotify('workbench.view.search.focus')<CR>")

-- couldn't get this one to work either
-- vim.keymap.set("n", "<M-r>", ":call VSCodeNotify('workbench.action.reloadWindow')<CR>")
vim.keymap.set("n", "<c-o>", ":call VSCodeNotify('workbench.action.openRecent')<CR>")

-- this doesn't work for some reason
-- vim.api.nvim_create_user_command("Git", "call VSCodeNotify('workbench.scm.focus')", {nargs = 1})

vim.keymap.set("n", "]g", ":call VSCodeNotify('workbench.action.editor.nextChange')<CR>")
vim.keymap.set("n", "[g", ":call VSCodeNotify('workbench.action.editor.previousChange')<CR>")

-- these don't work for some reason. Use c-w h instead
-- vim.keymap.set("n", "<c-h>", ":call VSCodeNotify('workbench.action.focusLeftGroup')<CR>")
-- vim.keymap.set("n", "<c-l>", ":call VSCodeNotify('workbench.action.focusRightGroup')<CR>")

require "config/hop"
-- require "config/lsp"
-- require "config/completion-and-snippets"
-- require "config/lualine"
-- require "config/formatter"
-- require "config/treesitter"
-- require "config/harpoon"
-- require "config/trouble"
-- require "config/lua-dev"
-- require "config/telescope"
-- require "config/terraform"