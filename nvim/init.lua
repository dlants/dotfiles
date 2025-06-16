-- This is the main init.lua that determines which configuration to load

-- Set leader keys (shared between VSCode and normal mode)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Large file handling
local function setup_large_file_optimizations()
  local large_file_size = 5 * 1024 * 1024 -- 5MB threshold

  vim.api.nvim_create_autocmd("BufReadPre", {
    callback = function(args)
      local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(args.buf))
      if ok and stats and stats.size > large_file_size then
        -- Disable syntax highlighting
        vim.cmd("syntax off")

        -- Disable fold calculations
        vim.opt_local.foldmethod = "manual"
        vim.opt_local.foldenable = false

        -- Disable swap file
        vim.opt_local.swapfile = false

        -- Disable undo persistence
        vim.opt_local.undofile = false

        -- Disable line numbers for better performance
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false

        -- Disable cursorline/cursorcolumn
        vim.opt_local.cursorline = false
        vim.opt_local.cursorcolumn = false

        -- Reduce updatetime
        vim.opt_local.updatetime = 10000

        -- Disable some expensive options
        vim.opt_local.showmatch = false
        vim.opt_local.spell = false

        -- Print notification
        vim.notify("Large file detected. Optimizations applied for better performance.", vim.log.levels.INFO)
      end
    end,
  })
end

setup_large_file_optimizations()

-- Check if running inside VSCode
if vim.g.vscode then
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
else
  -- Standard Neovim settings (when not in VSCode)
  -- disable netrw at the very start of your init.lua (strongly advised)
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

  -- set termguicolors to enable highlight groups
  vim.opt.termguicolors = true

  require "config.lazy"
  require "dev"

  vim.cmd "filetype plugin indent on"

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
end
