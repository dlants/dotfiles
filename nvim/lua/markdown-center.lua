-- Centers markdown buffers in a floating window overlay.
-- When a markdown file is displayed in a wide window, a narrower
-- floating window is created on top, giving a centered soft-wrap effect.

local M = {}

local MAX_WIDTH = 80
-- parent_win_id -> { float_win, scratch_buf, md_buf }
local active = {}
local guard = false

local function is_markdown(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  return vim.bo[buf].filetype == "markdown"
end

local function calc_float_config(parent_win)
  local w = vim.api.nvim_win_get_width(parent_win)
  local h = vim.api.nvim_win_get_height(parent_win)
  local pos = vim.api.nvim_win_get_position(parent_win)
  local fw = math.min(MAX_WIDTH, w)
  return {
    relative = "editor",
    width = fw,
    height = h,
    row = pos[1],
    col = pos[2] + math.floor((w - fw) / 2),
    focusable = true,
    zindex = 50,
  }
end

local function teardown(parent_win)
  local s = active[parent_win]
  if not s then return end
  active[parent_win] = nil
  if vim.api.nvim_win_is_valid(s.float_win) then
    vim.api.nvim_win_close(s.float_win, true)
  end
  if vim.api.nvim_buf_is_valid(s.scratch_buf) then
    pcall(vim.api.nvim_buf_delete, s.scratch_buf, { force = true })
  end
end

local function setup_float(win, buf)
  if active[win] or guard then return end
  if vim.api.nvim_win_get_width(win) <= MAX_WIDTH then return end

  guard = true

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].buftype = "nofile"

  local focused = (vim.api.nvim_get_current_win() == win)
  vim.api.nvim_win_set_buf(win, scratch)
  -- Make padding area invisible
  vim.wo[win].fillchars = "eob: "
  vim.wo[win].winhighlight = "StatusLine:Normal,StatusLineNC:Normal"

  local cfg = calc_float_config(win)
  local fw = vim.api.nvim_open_win(buf, focused, cfg)

  vim.wo[fw].wrap = true
  vim.wo[fw].linebreak = true
  vim.wo[fw].breakindent = true
  vim.wo[fw].cursorline = true
  vim.wo[fw].cursorcolumn = false
  vim.wo[fw].number = true
  vim.wo[fw].relativenumber = true
  vim.wo[fw].signcolumn = "no"
  vim.wo[fw].colorcolumn = ""
  -- Use Normal bg so float doesn't look different
  vim.wo[fw].winhighlight = "NormalFloat:Normal"

  active[win] = { float_win = fw, scratch_buf = scratch, md_buf = buf }
  guard = false
end

local function find_parent(float_win)
  for pw, s in pairs(active) do
    if s.float_win == float_win then return pw, s end
  end
end

local function navigate(dir)
  local cur = vim.api.nvim_get_current_win()
  local pw = find_parent(cur)
  if pw then
    guard = true
    vim.api.nvim_set_current_win(pw)
    vim.cmd("wincmd " .. dir)
    local landed = vim.api.nvim_get_current_win()
    guard = false
    if landed == pw then
      vim.api.nvim_set_current_win(cur)
    end
  else
    vim.cmd("wincmd " .. dir)
  end
end

local function on_win_enter()
  if guard then return end
  local win = vim.api.nvim_get_current_win()
  local s = active[win]
  if s and vim.api.nvim_win_is_valid(s.float_win) then
    guard = true
    vim.api.nvim_set_current_win(s.float_win)
    guard = false
  end
end

local function on_buf_enter()
  if guard then return end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()

  -- Case 1: inside a float window
  local pw, s = find_parent(win)
  if pw then
    if not is_markdown(buf) then
      guard = true
      local cursor = vim.api.nvim_win_get_cursor(win)
      teardown(pw)
      if vim.api.nvim_win_is_valid(pw) then
        vim.api.nvim_win_set_buf(pw, buf)
        vim.api.nvim_set_current_win(pw)
        pcall(vim.api.nvim_win_set_cursor, pw, cursor)
      end
      guard = false
    else
      s.md_buf = buf
    end
    return
  end

  -- Case 2: regular window showing a markdown buffer
  if is_markdown(buf) and not active[win] then
    setup_float(win, buf)
  end
end

local function on_resize()
  if guard then return end
  for pw, s in pairs(active) do
    if vim.api.nvim_win_is_valid(pw) and vim.api.nvim_win_is_valid(s.float_win) then
      local cfg = calc_float_config(pw)
      vim.api.nvim_win_set_config(s.float_win, cfg)
    else
      teardown(pw)
    end
  end
end

local function on_win_closed(ev)
  local closed = tonumber(ev.match)
  if active[closed] then
    teardown(closed)
    return
  end
  for pw, s in pairs(active) do
    if s.float_win == closed then
      active[pw] = nil
      if vim.api.nvim_win_is_valid(pw) and vim.api.nvim_buf_is_valid(s.md_buf) then
        vim.api.nvim_win_set_buf(pw, s.md_buf)
      end
      pcall(vim.api.nvim_buf_delete, s.scratch_buf, { force = true })
      break
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  MAX_WIDTH = opts.max_width or 80

  local g = vim.api.nvim_create_augroup("MarkdownCenter", { clear = true })

  vim.api.nvim_create_autocmd("WinEnter", { group = g, callback = on_win_enter })
  vim.api.nvim_create_autocmd("BufEnter", { group = g, callback = on_buf_enter })
  vim.api.nvim_create_autocmd("FileType", {
    group = g,
    pattern = "markdown",
    callback = function() vim.schedule(on_buf_enter) end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, { group = g, callback = on_resize })
  vim.api.nvim_create_autocmd("WinClosed", { group = g, callback = on_win_closed })

  for _, dir in ipairs({ "h", "j", "k", "l" }) do
    vim.keymap.set("n", "<C-" .. dir .. ">", function() navigate(dir) end, { noremap = true, silent = true })
  end
end

return M

