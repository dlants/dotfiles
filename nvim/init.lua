-- Neovim configuration
-- Set leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"



-- Visual line scrolling functions
local function scroll_up_visual()
  local count = math.floor(vim.fn.winheight(0) / 2)
  for i = 1, count do
    vim.cmd('normal! gk')
  end
  vim.cmd('normal! zz')
end

local function scroll_down_visual()
  local count = math.floor(vim.fn.winheight(0) / 2)
  for i = 1, count do
    vim.cmd('normal! gj')
  end
  vim.cmd('normal! zz')
end

-- Setup markdown/wrapped line mode
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "txt" },
  callback = function()
    -- Enable line wrapping
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true

    -- Map j and k to move by visual lines
    vim.keymap.set("n", "j", "gj", { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("n", "k", "gk", { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("v", "j", "gj", { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("v", "k", "gk", { buffer = 0, noremap = true, silent = true })

    -- Map $ and 0 to move by visual lines
    vim.keymap.set("n", "$", "g$", { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("n", "0", "g0", { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("v", "$", "g$", { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("v", "0", "g0", { buffer = 0, noremap = true, silent = true })

    -- Map Ctrl-u/d to scroll by visual lines
    vim.keymap.set("n", "<C-u>", scroll_up_visual, { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("n", "<C-d>", scroll_down_visual, { buffer = 0, noremap = true, silent = true })
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
vim.o.scrolloff = 1
vim.o.shiftwidth = 2
vim.o.softtabstop = 0
vim.o.expandtab = true

if vim.loop.os_uname().sysname == "Darwin" then
  vim.o.shell = "/opt/homebrew/bin/zsh"
end

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

-- GitHub browse commands using gh CLI
local function gh_browse(opts)
  local file = vim.fn.expand("%")
  local branch = opts.branch

  local cmd = "gh browse " .. vim.fn.shellescape(file)
  if branch then
    cmd = cmd .. " -b " .. branch
  end

  vim.fn.system(cmd)
end

local function gh_browse_lines(opts)
  local file = vim.fn.expand("%")
  local branch = opts.branch
  local start_line, end_line

  if opts.range > 0 then
    start_line = opts.line1
    end_line = opts.line2
  else
    start_line = vim.fn.line(".")
    end_line = start_line
  end

  local file_with_lines
  if start_line == end_line then
    file_with_lines = file .. ":" .. start_line
  else
    file_with_lines = file .. ":" .. start_line .. "-" .. end_line
  end

  local cmd = "gh browse " .. vim.fn.shellescape(file_with_lines)
  if branch then
    cmd = cmd .. " -b " .. branch
  end

  vim.fn.system(cmd)
end

vim.api.nvim_create_user_command("Gho", function() gh_browse({}) end, {})
vim.api.nvim_create_user_command("Ghom", function() gh_browse({ branch = "main" }) end, {})
vim.api.nvim_create_user_command("Ghl", function(opts) gh_browse_lines(opts) end, { range = true })
vim.api.nvim_create_user_command("Ghlm",
  function(opts) gh_browse_lines({ range = opts.range, line1 = opts.line1, line2 = opts.line2, branch = "main" }) end,
  { range = true })
