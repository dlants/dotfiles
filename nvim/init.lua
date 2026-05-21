-- Neovim configuration

-- Capture nvim start time as epoch ms. Used by magenta (and anything else)
-- to produce a unified timing timeline across lua and subprocesses.
do
  local sec, usec = vim.uv.gettimeofday()
  vim.g.nvim_start_time_ms = sec * 1000 + usec / 1000
end

-- Set leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- OS-specific settings
local is_linux = vim.loop.os_uname().sysname == "Linux"

if is_linux then
  vim.o.clipboard = 'unnamedplus'

  -- Use OSC52 for copying (works through tmux+ssh)
  -- For pasting: read from shared clipboard file (synced from host)
  -- OSC52 paste doesn't work through tmux: https://github.com/tmux/tmux/issues/3068
  local clipboard_file = '/home/aurelia/dev-in-docker-shared-files/clipboard.txt'

  vim.g.clipboard = {
    name = 'OSC 52 + shared file',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = { 'cat', clipboard_file },
      ['*'] = { 'cat', clipboard_file },
    },
  }
end

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

-- Open a file in another window if available, otherwise create a vsplit
local function open_file_in_other_window(abs_path)
  local cur_win = vim.api.nvim_get_current_win()
  local cur_is_magenta = pcall(vim.api.nvim_win_get_var, cur_win, "magenta")

  local buf = vim.fn.bufadd(abs_path)
  vim.fn.bufload(buf)

  if not cur_is_magenta then
    vim.api.nvim_win_set_buf(cur_win, buf)
    return
  end

  -- Current window is magenta, find a non-magenta window
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local is_magenta = pcall(vim.api.nvim_win_get_var, win, "magenta")
    if not is_magenta then
      vim.api.nvim_win_set_buf(win, buf)
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  -- No non-magenta window found, create a full-height split
  vim.api.nvim_open_win(buf, true, {
    win = -1,
    split = "right",
  })
end



-- Setup markdown/wrapped line mode
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "txt" },
  callback = function()
    -- Enable soft wrapping, disable hard wrapping
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.textwidth = 0
    vim.opt_local.formatoptions:remove({ "t", "c" })

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

    -- Open URL or file under cursor with <CR>
    vim.keymap.set("n", "<CR>", function()
      local word = vim.fn.expand("<cWORD>")
      -- Extract from markdown link syntax [text](target) or bare URL
      local target = word:match("%]%((.+)%)")
          or word:match("https?://[%w%-._~:/?#%[%]@!$&'()*+,;%%=]+")

      if not target then
        -- Try plain file path under cursor
        target = vim.fn.expand("<cfile>")
        if target == "" or target:match("^https?://") then
          return
        end
        local md_dir = vim.fn.expand("%:p:h")
        local abs_path = vim.fn.fnamemodify(md_dir .. "/" .. target, ":p")
        if vim.fn.filereadable(abs_path) == 1 then
          open_file_in_other_window(abs_path)
        end
        return
      end

      if target:match("^https?://") then
        vim.fn.system({ "open", target })
      else
        local md_dir = vim.fn.expand("%:p:h")
        local abs_path = md_dir .. "/" .. target
        if vim.fn.filereadable(abs_path) == 1 then
          open_file_in_other_window(abs_path)
        end
      end
    end, { buffer = 0, noremap = true, silent = true })
    -- Map Ctrl-u/d to scroll by visual lines
    vim.keymap.set("n", "<C-u>", scroll_up_visual, { buffer = 0, noremap = true, silent = true })
    vim.keymap.set("n", "<C-d>", scroll_down_visual, { buffer = 0, noremap = true, silent = true })
  end,
})

vim.g.markdown_recommended_style = 0

-- disable netrw at the very start of your init.lua (strongly advised)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

require "config.pack"
require "config.plugins"
require "dev"
require("dashboard").setup()
require("needle").setup()
require("shuck").setup({})
-- require("markdown-center").setup({ max_width = 120 })

vim.cmd "filetype plugin indent on"

vim.o.background = "dark"
vim.o.number = true
vim.o.tabstop = 2
vim.o.scrolloff = 1
vim.o.shiftwidth = 2
vim.o.softtabstop = 0
vim.o.expandtab = true

if not is_linux then
  vim.o.clipboard = "unnamedplus"
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

-- Snapshot jj status on markdown write to track work progress
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = vim.fn.expand("~") .. "/src/amusements/*.md",
  callback = function()
    local cwd = vim.fn.getcwd()
    if vim.fn.isdirectory(cwd .. "/.jj") == 1 then
      vim.fn.jobstart({ "jj", "status" }, { cwd = cwd })
    end
  end,
})

-- Escalating pane navigation: neovim splits → tmux panes → macOS windows.
-- Falls through to the pane-nav helper script when at the edge of nvim splits.
local function pane_navigate(wincmd, tmux_dir)
  local cur_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. wincmd)
  if cur_win == vim.api.nvim_get_current_win() then
    vim.fn.jobstart({ "pane-nav", tmux_dir }, { detach = true })
  end
end

vim.keymap.set("n", "<C-h>", function() pane_navigate("h", "L") end, { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", function() pane_navigate("j", "D") end, { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", function() pane_navigate("k", "U") end, { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", function() pane_navigate("l", "R") end, { noremap = true, silent = true })

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
vim.api.nvim_set_keymap("n", "<leader>n", ":botright vsplit | enew<CR>",
  { noremap = true, silent = true, desc = "New buffer in rightmost vertical split" })

local default_branch_cache = {}

local function get_default_branch()
  local toplevel = vim.trim(vim.fn.system("git rev-parse --show-toplevel"))
  if default_branch_cache[toplevel] then
    return default_branch_cache[toplevel]
  end
  local result = vim.trim(vim.fn.system("gh repo view --json defaultBranchRef --jq .defaultBranchRef.name"))
  default_branch_cache[toplevel] = result
  return result
end

local function get_current_branch()
  local branch = vim.trim(vim.fn.system("git branch --show-current"))
  if branch == "" then
    branch = vim.trim(vim.fn.system("git rev-parse HEAD"))
  end
  return branch
end

local function get_repo_relative_path()
  local abs_path = vim.fn.expand("%:p")
  local toplevel = vim.trim(vim.fn.system("git rev-parse --show-toplevel"))
  if toplevel ~= "" and vim.startswith(abs_path, toplevel .. "/") then
    return abs_path:sub(#toplevel + 2)
  end
  return vim.fn.expand("%")
end

-- GitHub browse commands using gh CLI
local function resolve_branch(opts)
  if opts.branch == "default" then
    return get_default_branch()
  end
  return get_current_branch()
end

local function gh_browse(opts)
  local file = get_repo_relative_path()
  local branch = resolve_branch(opts)
  local toplevel = vim.trim(vim.fn.system("git rev-parse --show-toplevel"))
  local cmd = "cd " .. vim.fn.shellescape(toplevel) .. " && gh browse "
      .. vim.fn.shellescape(file) .. " -b " .. vim.fn.shellescape(branch)
  vim.fn.system(cmd)
end

local function gh_browse_lines(opts)
  local file = get_repo_relative_path()
  local branch = resolve_branch(opts)
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

  local toplevel = vim.trim(vim.fn.system("git rev-parse --show-toplevel"))
  local cmd = "cd " .. vim.fn.shellescape(toplevel) .. " && gh browse "
      .. vim.fn.shellescape(file_with_lines) .. " -b " .. vim.fn.shellescape(branch)
  vim.fn.system(cmd)
end

vim.api.nvim_create_user_command("Gho", function() gh_browse({}) end, {})
vim.api.nvim_create_user_command("Ghom", function() gh_browse({ branch = "default" }) end, {})
vim.api.nvim_create_user_command("Ghl", function(opts) gh_browse_lines(opts) end, { range = true })
vim.api.nvim_create_user_command("Ghlm",
  function(opts) gh_browse_lines({ range = opts.range, line1 = opts.line1, line2 = opts.line2, branch = "default" }) end,
  { range = true })
