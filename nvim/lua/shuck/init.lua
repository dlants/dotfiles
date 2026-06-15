-- shuck: streamed shell-command picker (vim-grepper replacement) for neovim.
local M = {}
local uv = vim.uv or vim.loop
local api = vim.api

-- ============================================================================
-- Config
-- ============================================================================

M.config = {
  default_cmd     = "rg -H --no-heading --vimgrep ",
  max_render      = 200,
  max_results     = 10000,
  stream_flush_ms = 30,
  spinner_ms      = 80,
}

-- ============================================================================
-- State
-- ============================================================================

local state = nil
local NS_HL = api.nvim_create_namespace("shuck_hl")
local NS_PROMPT = api.nvim_create_namespace("shuck_prompt")
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- ============================================================================
-- Helpers
-- ============================================================================

local function kill_child()
  if not state then return end
  if state.child then
    pcall(function() state.child:kill("sigterm") end)
    state.child = nil
  end
  state.running = false
end

local function set_title()
  if not state or not api.nvim_win_is_valid(state.results_win) then return end
  local n = #state.output_lines
  local marker
  if state.running then
    marker = SPINNER_FRAMES[(state.spinner_idx % #SPINNER_FRAMES) + 1]
  else
    marker = "•"
  end
  local title
  if state.truncated then
    title = string.format(" shuck %s %d lines (truncated) ", marker, n)
  else
    title = string.format(" shuck %s %d lines ", marker, n)
  end
  pcall(api.nvim_set_option_value, "winbar", title, { win = state.results_win })
end

local function close_picker()
  if not state then return end
  pcall(vim.cmd, "stopinsert")
  kill_child()
  if state.flush_timer then
    pcall(function() state.flush_timer:stop() end)
    pcall(function() state.flush_timer:close() end)
  end
  if state.spinner_timer then
    pcall(function() state.spinner_timer:stop() end)
    pcall(function() state.spinner_timer:close() end)
  end
  for _, win in ipairs({ state.prompt_win, state.results_win }) do
    if win and api.nvim_win_is_valid(win) then pcall(api.nvim_win_close, win, true) end
  end
  for _, buf in ipairs({ state.prompt_buf, state.results_buf }) do
    if buf and api.nvim_buf_is_valid(buf) then pcall(api.nvim_buf_delete, buf, { force = true }) end
  end
  state = nil
end

local function discover_search_dir(opts_cwd, buf_name)
  if opts_cwd and opts_cwd ~= "" then return opts_cwd end
  local current_cwd = vim.fn.getcwd()
  if not buf_name or buf_name == "" then return current_cwd end
  local buf_dir
  local oil = buf_name:match("^oil://(.*)$")
  if oil then
    buf_dir = oil:gsub("/+$", "")
  elseif buf_name:match("^%w+://") then
    return current_cwd
  else
    buf_dir = vim.fs.dirname(buf_name)
  end
  if buf_dir == current_cwd or buf_dir:sub(1, #current_cwd + 1) == current_cwd .. "/" then
    return current_cwd
  end
  local found = vim.fs.find(".git", { upward = true, path = buf_dir })
  if found and #found > 0 then return vim.fs.dirname(found[1]) end
  return buf_dir
end

-- ============================================================================
-- History
-- ============================================================================

local function history_file_path(cwd)
  local dir = vim.fn.stdpath("data") .. "/shuck"
  vim.fn.mkdir(dir, "p")
  local hash = vim.fn.sha256(cwd):sub(1, 16)
  return dir .. "/" .. hash .. ".txt"
end

local function load_history(cwd)
  local path = history_file_path(cwd)
  local f = io.open(path, "r")
  if not f then return {} end
  local lines = {}
  for line in f:lines() do
    if line ~= "" then lines[#lines + 1] = line end
  end
  f:close()
  return lines
end

local function save_history(cwd, history)
  local path = history_file_path(cwd)
  local f = io.open(path, "w")
  if not f then return end
  for _, line in ipairs(history) do
    f:write(line, "\n")
  end
  f:close()
end

local function record_history(cwd, cmd, history)
  if not cmd or cmd:match("^%s*$") then return history end
  local new = { cmd }
  for _, h in ipairs(history) do
    if h ~= cmd then new[#new + 1] = h end
  end
  while #new > 200 do new[#new] = nil end
  save_history(cwd, new)
  return new
end

local function reset_history_cycle()
  if not state then return end
  state.history_idx = nil
  state.history_prefix = nil
  state.history_original = nil
  state.history_filtered = nil
end

local function set_prompt(text)
  if not state or not api.nvim_buf_is_valid(state.prompt_buf) then return end
  api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, { text })
  state.cmd_string = text
  if api.nvim_win_is_valid(state.prompt_win) then
    pcall(api.nvim_win_set_cursor, state.prompt_win, { 1, #text })
  end
end

-- Resolve the search root lazily (the upward `.git` walk is the slow part of
-- startup, so we defer it off the path that paints the UI). Idempotent.
local function resolve_cwd()
  if not state or state.cwd_resolved then return state and state.cwd end
  state.cwd_resolved = true
  local cwd = discover_search_dir(state.opts_cwd, state.origin_buf_name)
  state.cwd = cwd
  state.history = load_history(cwd)
  local main_cwd = vim.fn.getcwd()
  if cwd ~= main_cwd and api.nvim_buf_is_valid(state.prompt_buf) then
    local display_dir = vim.fn.fnamemodify(cwd, ":~")
    api.nvim_buf_set_extmark(state.prompt_buf, NS_PROMPT, 0, 0, {
      virt_text = { { string.format("cd %s && ", display_dir), "Comment" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end
  set_title()
  return cwd
end

-- ============================================================================
-- Rendering
-- ============================================================================

local function render_results()
  if not state or not api.nvim_buf_is_valid(state.results_buf) then return end
  if state.picker_mode then return end
  local n = #state.output_lines
  local max_render = M.config.max_render
  local count = math.min(n, max_render)

  local lines = {}
  for i = 1, count do lines[i] = state.output_lines[i] end
  if count == 0 then lines = { "" } end

  api.nvim_set_option_value("modifiable", true, { buf = state.results_buf })
  api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(state.results_buf, NS_HL, 0, -1)
  state.rendered_count = count

  if count > 0 then
    state.selected = math.max(1, math.min(state.selected, n))
    if state.selected <= count then
      api.nvim_buf_set_extmark(state.results_buf, NS_HL, state.selected - 1, 0, {
        end_row = state.selected,
        hl_group = "ShuckSel",
        hl_eol = true,
        priority = 200,
      })
    end
  end
  api.nvim_set_option_value("modifiable", false, { buf = state.results_buf })

  if api.nvim_win_is_valid(state.results_win) and count > 0 and state.selected <= count then
    pcall(api.nvim_win_set_cursor, state.results_win, { state.selected, 0 })
  end

  set_title()
end

local function schedule_flush()
  if not state then return end
  if not state.flush_timer then state.flush_timer = uv.new_timer() end
  state.flush_timer:stop()
  state.flush_timer:start(M.config.stream_flush_ms, 0, vim.schedule_wrap(function()
    if state then render_results() end
  end))
end

-- ============================================================================
-- Streaming chunk handler
-- ============================================================================

local function maybe_rewrite_path(line)
  if not state or not state.rewrite_paths then return line end
  local file, rest = line:match("^([^:]+)(:.*)$")
  if file and file:sub(1, 1) ~= "/" then
    return state.cwd .. "/" .. file .. rest
  end
  return line
end

local function handle_chunk(chunk, pending_field, prefix)
  if not state then return false end
  local cap = M.config.max_results
  if #state.output_lines >= cap then return true end

  state[pending_field] = state[pending_field] .. chunk
  local pending = state[pending_field]
  local start = 1
  local hit = false
  while true do
    local nl = pending:find("\n", start, true)
    if not nl then break end
    local line = pending:sub(start, nl - 1)
    start = nl + 1
    if line ~= "" then
      if prefix == nil then line = maybe_rewrite_path(line) end
      state.output_lines[#state.output_lines + 1] = (prefix or "") .. line
      if #state.output_lines >= cap then hit = true; break end
    end
  end
  state[pending_field] = pending:sub(start)
  return hit
end

-- ============================================================================
-- Command execution
-- ============================================================================

local function run_command()
  if not state then return end
  resolve_cwd()
  local lines = api.nvim_buf_get_lines(state.prompt_buf, 0, -1, false)
  state.cmd_string = lines[1] or ""
  if state.cmd_string:match("^%s*$") then return end

  state.history = record_history(state.cwd, state.cmd_string, state.history)
  reset_history_cycle()
  state.picker_mode = false

  kill_child()

  state.run_epoch = (state.run_epoch or 0) + 1
  local epoch = state.run_epoch

  state.output_lines = {}
  state.pending_chunk = ""
  state.stderr_pending = ""
  state.rendered_count = 0
  state.selected = 1
  state.running = true
  state.truncated = false
  state.stale = false
  state.rewrite_paths = (state.cwd ~= vim.fn.getcwd())

  api.nvim_set_option_value("modifiable", true, { buf = state.results_buf })
  api.nvim_buf_set_lines(state.results_buf, 0, -1, false, {})
  api.nvim_set_option_value("modifiable", false, { buf = state.results_buf })

  if not state.spinner_timer then state.spinner_timer = uv.new_timer() end
  state.spinner_idx = 0
  state.spinner_timer:stop()
  state.spinner_timer:start(M.config.spinner_ms, M.config.spinner_ms, vim.schedule_wrap(function()
    if not state or not state.running then return end
    state.spinner_idx = (state.spinner_idx + 1) % #SPINNER_FRAMES
    set_title()
  end))

  set_title()

  state.child = vim.system({ "sh", "-c", state.cmd_string }, {
    cwd = state.cwd,
    text = true,
    stdout = function(err, data)
      if err or not data or data == "" then return end
      vim.schedule(function()
        if not state or state.run_epoch ~= epoch then return end
        local hit = handle_chunk(data, "pending_chunk", nil)
        if hit then
          state.truncated = true
          kill_child()
        end
        schedule_flush()
      end)
    end,
    stderr = function(err, data)
      if err or not data or data == "" then return end
      vim.schedule(function()
        if not state or state.run_epoch ~= epoch then return end
        local hit = handle_chunk(data, "stderr_pending", "!! ")
        if hit then
          state.truncated = true
          kill_child()
        end
        schedule_flush()
      end)
    end,
  }, function(_)
    vim.schedule(function()
      if not state or state.run_epoch ~= epoch then return end
      local cap = M.config.max_results
      if state.pending_chunk ~= "" and #state.output_lines < cap then
        state.output_lines[#state.output_lines + 1] = maybe_rewrite_path(state.pending_chunk)
      end
      state.pending_chunk = ""
      if state.stderr_pending ~= "" and #state.output_lines < cap then
        state.output_lines[#state.output_lines + 1] = "!! " .. state.stderr_pending
      end
      state.stderr_pending = ""
      state.running = false
      if state.spinner_timer then
        pcall(function() state.spinner_timer:stop() end)
      end
      render_results()
    end)
  end)
end

-- ============================================================================
-- Selection / actions
-- ============================================================================

local function move_selection(delta)
  if not state then return end
  local n = #state.output_lines
  if n == 0 then return end
  state.selected = ((state.selected - 1 + delta) % n) + 1
  render_results()
end

local function open_selected(open_cmd)
  if not state then return end
  local line = state.output_lines[state.selected]
  if not line then return end
  local file, lnum, col = line:match("^([^:]+):(%d+):(%d+):")
  if not file then return end
  lnum = tonumber(lnum)
  col = tonumber(col)
  local cwd = state.cwd
  local origin_win = state.origin_win
  local origin_full_height = state.origin_full_height
  open_cmd = open_cmd or "edit"
  close_picker()
  local abs = file
  if file:sub(1, 1) ~= "/" then
    abs = cwd .. "/" .. file
  end
  local valid_origin = origin_win and api.nvim_win_is_valid(origin_win)
  if valid_origin then
    api.nvim_set_current_win(origin_win)
  end
  if open_cmd == "edit" and (not valid_origin or not origin_full_height) then
    vim.cmd("botright vsplit")
  end
  vim.cmd(open_cmd .. " " .. vim.fn.fnameescape(abs))
  pcall(api.nvim_win_set_cursor, 0, { lnum, math.max(0, col - 1) })
  pcall(vim.cmd, "normal! zz")
end

local function to_quickfix()
  if not state then return end
  kill_child()
  local lines = state.output_lines
  local title = state.cmd_string or "shuck"
  vim.fn.setqflist({}, " ", {
    title = title,
    lines = lines,
    efm = "%f:%l:%c:%m",
  })
  close_picker()
  vim.cmd("copen")
end

-- ============================================================================
-- History UI
-- ============================================================================

local function render_history_picker()
  if not state or not api.nvim_buf_is_valid(state.results_buf) then return end

  api.nvim_set_option_value("modifiable", true, { buf = state.results_buf })
  api.nvim_buf_set_lines(state.results_buf, 0, -1, false, state.history)
  api.nvim_buf_clear_namespace(state.results_buf, NS_HL, 0, -1)

  if #state.history > 0 then
    local sel = state.picker_selected
    api.nvim_buf_set_extmark(state.results_buf, NS_HL, sel - 1, 0, {
      end_row = sel,
      hl_group = "ShuckSel",
      hl_eol = true,
      priority = 200,
    })
    if api.nvim_win_is_valid(state.results_win) then
      pcall(api.nvim_win_set_cursor, state.results_win, { sel, 0 })
    end
  end
  api.nvim_set_option_value("modifiable", false, { buf = state.results_buf })
end

local function history_cycle(direction)
  if not state then return end
  resolve_cwd()
  if #state.history == 0 then return end

  if state.history_idx == nil then
    state.history_prefix = state.cmd_string or ""
    state.history_original = state.cmd_string or ""
    state.history_filtered = {}
    for _, h in ipairs(state.history) do
      if h:sub(1, #state.history_prefix) == state.history_prefix then
        state.history_filtered[#state.history_filtered + 1] = h
      end
    end
  end

  local n = #state.history_filtered
  if n == 0 then return end

  if state.history_idx == nil then
    if direction == 1 then
      state.history_idx = 1
    else
      return
    end
  else
    state.history_idx = state.history_idx + direction
    if state.history_idx < 1 then
      state.history_idx = nil
      set_prompt(state.history_original)
      return
    elseif state.history_idx > n then
      state.history_idx = n
    end
  end

  set_prompt(state.history_filtered[state.history_idx])
end

local function start_history_picker()
  if not state then return end
  resolve_cwd()
  if #state.history == 0 then return end
  pcall(vim.cmd, "stopinsert")
  state.picker_mode = true
  state.picker_selected = 1
  set_prompt(state.history[1])
  render_history_picker()
end

local function picker_move(delta)
  if not state or not state.picker_mode then return end
  local n = #state.history
  if n == 0 then return end
  state.picker_selected = ((state.picker_selected - 1 + delta) % n) + 1
  set_prompt(state.history[state.picker_selected])
  render_history_picker()
end

local function exit_picker(run)
  if not state or not state.picker_mode then return end
  state.picker_mode = false
  if run then
    run_command()
  else
    render_results()
    pcall(vim.cmd, "startinsert!")
  end
end

-- ============================================================================
-- UI: floating windows + keymaps
-- ============================================================================

local function open_windows()
  local total_h = vim.o.lines
  local picker_height = math.max(math.floor(total_h * 0.3), 6)
  local results_height = picker_height - 1

  local prompt_buf = api.nvim_create_buf(false, true)
  local results_buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = prompt_buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = results_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = prompt_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = results_buf })
  api.nvim_set_option_value("filetype", "shuck", { buf = prompt_buf })
  api.nvim_set_option_value("filetype", "shuck", { buf = results_buf })

  vim.cmd("topleft 1split")
  local prompt_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(prompt_win, prompt_buf)
  api.nvim_set_option_value("winfixheight", true, { win = prompt_win })

  vim.cmd("belowright " .. results_height .. "split")
  local results_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(results_win, results_buf)
  api.nvim_set_option_value("cursorline", false, { win = results_win })
  api.nvim_set_option_value("wrap", false, { win = results_win })
  api.nvim_set_option_value("winfixheight", true, { win = results_win })
  api.nvim_set_option_value("winbar", " shuck ", { win = results_win })

  api.nvim_set_current_win(prompt_win)

  return prompt_buf, prompt_win, results_buf, results_win
end

local function setup_keymaps(prompt_buf)
  local function map(modes, lhs, fn)
    for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
      api.nvim_buf_set_keymap(prompt_buf, mode, lhs, "", {
        noremap = true, silent = true, callback = fn,
      })
    end
  end

  map({"i","n"}, "<CR>",   function()
    if state and state.picker_mode then exit_picker(false)
    else open_selected("edit") end
  end)
  map({"i","n"}, "<C-CR>", function()
    if state and state.picker_mode then exit_picker(true)
    else run_command() end
  end)
  map({"i","n"}, "<C-j>",  function()
    if state and state.picker_mode then picker_move(1)
    else move_selection(1) end
  end)
  map({"i","n"}, "<C-k>",  function()
    if state and state.picker_mode then picker_move(-1)
    else move_selection(-1) end
  end)
  map({"i","n"}, "<C-d>",  function()
    if state and state.picker_mode then picker_move(10)
    else move_selection(10) end
  end)
  map({"i","n"}, "<C-u>",  function()
    if state and state.picker_mode then picker_move(-10)
    else move_selection(-10) end
  end)
  map({"i","n"}, "<Up>",   function()
    if state and state.picker_mode then picker_move(-1)
    else history_cycle(1) end
  end)
  map({"i","n"}, "<Down>", function()
    if state and state.picker_mode then picker_move(1)
    else history_cycle(-1) end
  end)
  map("n",       "<C-r>",  function() start_history_picker() end)
  map({"i","n"}, "<C-x>",  function() open_selected("split") end)
  map({"i","n"}, "<C-v>",  function() open_selected("vsplit") end)
  map({"i","n"}, "<C-t>",  function() open_selected("tabedit") end)
  map("n", "q",            function() to_quickfix() end)
  map("n", "<Esc>",        function() close_picker() end)
  map({"i","n"}, "<C-c>",  function() close_picker() end)
end

-- ============================================================================
-- Public API
-- ============================================================================

function M.open(opts)
  opts = opts or {}
  if state then close_picker() end

  local origin_win = api.nvim_get_current_win()
  local is_floating = api.nvim_win_get_config(origin_win).relative ~= ""
  local origin_full_height = (not is_floating)
    and vim.fn.winnr("k") == vim.fn.winnr()
    and vim.fn.winnr("j") == vim.fn.winnr()

  -- Capture the originating buffer name now (cheap); the picker's own buffer
  -- is focused by the time we resolve the search root.
  local origin_buf_name = api.nvim_buf_get_name(api.nvim_get_current_buf())
  local prompt_buf, prompt_win, results_buf, results_win = open_windows()

  state = {
    prompt_buf      = prompt_buf,
    prompt_win      = prompt_win,
    results_buf     = results_buf,
    results_win     = results_win,
    cmd_string      = "",
    output_lines    = {},
    pending_chunk   = "",
    stderr_pending  = "",
    rendered_count  = 0,
    selected        = 1,
    running         = false,
    truncated       = false,
    stale           = false,
    cwd             = nil,
    cwd_resolved    = false,
    opts_cwd        = opts.cwd,
    origin_buf_name = origin_buf_name,
    spinner_idx     = 0,
    run_epoch       = 0,
    child           = nil,
    history          = {},
    history_idx      = nil,
    history_prefix   = nil,
    history_original = nil,
    history_filtered = nil,
    picker_mode      = false,
    picker_selected  = 1,
    origin_win         = origin_win,
    origin_full_height = origin_full_height,
  }

  local default_cmd = opts.cmd or M.config.default_cmd
  api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { default_cmd })
  state.cmd_string = default_cmd

  setup_keymaps(prompt_buf)

  api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt_buf,
    callback = function()
      if not state then return end
      local lines = api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
      state.cmd_string = lines[1] or ""
      state.stale = true

      if state.history_idx ~= nil and state.history_filtered then
        local expected = state.history_filtered[state.history_idx]
        if state.cmd_string ~= expected then
          reset_history_cycle()
        end
      end

      if state.picker_mode then
        local expected = state.history[state.picker_selected]
        if state.cmd_string ~= expected then
          state.picker_mode = false
          render_results()
        end
      end
    end,
  })

  api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(prompt_win), tostring(results_win) },
    callback = function() vim.schedule(close_picker) end,
  })

  set_title()
  vim.cmd("startinsert!")

  -- Defer the search-root resolution so the prompt is interactive immediately.
  vim.schedule(function()
    if state then resolve_cwd() end
  end)
end

function M.toggle(opts)
  if state then close_picker() else M.open(opts) end
end

function M.close()
  close_picker()
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  api.nvim_set_hl(0, "ShuckSel",   { link = "PmenuSel", default = true })
  api.nvim_set_hl(0, "ShuckMatch", { link = "Special",  default = true })

  api.nvim_create_user_command("Shuck", function() M.open() end, {})
end

return M
