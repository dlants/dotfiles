-- Neovim configuration
-- Set leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"



-- Setup markdown/wrapped line mode
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "txt" },
  callback = function()
    -- Enable line wrapping
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true

    -- Map j and k to move by visual lines
    vim.api.nvim_buf_set_keymap(0, "n", "j", "gj", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(0, "n", "k", "gk", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(0, "v", "j", "gj", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(0, "v", "k", "gk", { noremap = true, silent = true })

    -- Map $ and 0 to move by visual lines
    vim.api.nvim_buf_set_keymap(0, "n", "$", "g$", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(0, "n", "0", "g0", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(0, "v", "$", "g$", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(0, "v", "0", "g0", { noremap = true, silent = true })
  end,
})

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

-- Jump through jump list until buffer changes
local function jump_until_buffer_changes(direction)
  local current_buf = vim.api.nvim_get_current_buf()
  local max_attempts = 100 -- Prevent infinite loops
  local attempts = 0

  while attempts < max_attempts do
    attempts = attempts + 1

    -- Try to jump
    local success = pcall(function()
      if direction == "back" then
        vim.cmd("normal! \23\15") -- <C-O>
      else
        vim.cmd("normal! \23\9")  -- <C-I>
      end
    end)

    if not success then
      -- No more jumps available
      break
    end

    -- Check if buffer changed
    local new_buf = vim.api.nvim_get_current_buf()
    if new_buf ~= current_buf then
      break
    end
  end
end

vim.api.nvim_set_keymap("n", "[J", "<Cmd>lua jump_until_buffer_changes('back')<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "]J", "<Cmd>lua jump_until_buffer_changes('forward')<CR>",
  { noremap = true, silent = true })
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
