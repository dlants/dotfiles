-- Archived VSCode-Neovim configuration
-- This configuration was used when running Neovim inside VSCode
-- Kept for reference but no longer actively used

--[[
-- VSCode Neovim extension specific settings
vim.o.clipboard = "unnamedplus"
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.hlsearch = true

-- No need to disable netrw in VS Code mode

-- Bind dash key to open VS Code file explorer
vim.api.nvim_set_keymap("n", "-", "<Cmd>lua require('vscode').action('workbench.view.explorer')<CR>",
  { noremap = true, silent = true })

-- Add a command to reload Neovim config
vim.api.nvim_set_keymap("n", "<leader>sv", ":source $MYVIMRC<CR>", { noremap = true, silent = true })

-- No need for CheckOil command in VS Code mode

-- Override Q command to close editor group instead of just the current tab
vim.api.nvim_set_keymap("n", "Q", "<Cmd>lua require('vscode').action('workbench.action.closeEditorsInGroup')<CR>",
  { noremap = true, silent = true })

-- Override default gf to use VSCode file picker
vim.api.nvim_set_keymap("n", "gf", "<Cmd>lua require('vscode').action('workbench.action.quickOpen')<CR>",
  { noremap = true, silent = true })

-- VSCode-specific mappings
-- File navigation
vim.api.nvim_set_keymap("n", "<leader>f", "<Cmd>lua require('vscode').action('workbench.action.quickOpen')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>e",
  "<Cmd>lua require('vscode').action('workbench.action.toggleSidebarVisibility')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>b", "<Cmd>lua require('vscode').action('workbench.action.showAllEditors')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>k", "<Cmd>lua require('vscode').action('editor.action.showHover')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>g", "<Cmd>lua require('vscode').action('workbench.action.findInFiles')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>go", "<Cmd>lua require('vscode').action('gitlens.openFileOnRemote')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>gl", "<Cmd>lua require('vscode').action('gitlens.copyPermalink')<CR>",
  { noremap = true, silent = true })

-- Code actions
vim.api.nvim_set_keymap("n", "gr", "<Cmd>lua require('vscode').action('editor.action.goToReferences')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "gd", "<Cmd>lua require('vscode').action('editor.action.revealDefinition')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>`", "<Cmd>lua require('vscode').action('editor.action.formatDocument')<CR>",
  { noremap = true, silent = true })

-- Unimpaired-style mappings
vim.api.nvim_set_keymap("n", "[j", "<Cmd>lua require('vscode').action('workbench.action.navigateBack')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "]j", "<Cmd>lua require('vscode').action('workbench.action.navigateForward')<CR>",
  { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "[<space>", "O<Esc>j", { noremap = true })
vim.api.nvim_set_keymap("n", "]<space>", "o<Esc>k", { noremap = true })

-- Diagnostic navigation
vim.api.nvim_set_keymap("n", "[d", "<Cmd>lua require('vscode').action('editor.action.marker.prev')<CR>",
  { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "]d", "<Cmd>lua require('vscode').action('editor.action.marker.next')<CR>",
  { noremap = true, silent = true })
--]]