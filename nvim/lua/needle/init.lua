-- needle: fast, signal-aware file picker for neovim.
local M = {}
local uv = vim.uv or vim.loop
local api = vim.api
local score = require("needle.score")

-- ============================================================================
-- Future: single-shot, lazily-computed async value.
-- ============================================================================
-- `compute(resolve)` runs at most once, on the first :get(). It must call
-- resolve(value) exactly once (synchronously or later). Callbacks registered
-- via :get() fire immediately if already resolved, otherwise when it resolves.
local Future = {}
Future.__index = Future

function Future.new(compute)
  return setmetatable({ compute = compute, waiters = {} }, Future)
end

function Future:get(cb)
  if self.resolved then cb(self.value); return end
  self.waiters[#self.waiters + 1] = cb
  if self.started then return end
  self.started = true
  self.compute(function(value)
    if self.resolved then return end
    self.resolved = true
    self.value = value
    local waiters = self.waiters
    self.waiters = {}
    for _, w in ipairs(waiters) do w(value) end
  end)
end

-- ============================================================================
-- Config
-- ============================================================================

local function default_files_command(unrestricted)
  if vim.fn.executable("fd") == 1 then
    local cmd = { "fd", "--type", "f", "--hidden" }
    if unrestricted then table.insert(cmd, "--no-ignore") end
    table.insert(cmd, "--exclude"); table.insert(cmd, ".git")
    table.insert(cmd, "--exclude"); table.insert(cmd, "node_modules")
    return cmd
  elseif vim.fn.executable("rg") == 1 then
    local cmd = { "rg", "--files", "--hidden" }
    if unrestricted then table.insert(cmd, "--no-ignore") end
    table.insert(cmd, "--glob"); table.insert(cmd, "!.git/*")
    table.insert(cmd, "--glob"); table.insert(cmd, "!node_modules/*")
    return cmd
  else
    return { "find", ".", "-type", "f",
             "-not", "-path", "*/.git/*",
             "-not", "-path", "*/node_modules/*" }
  end
end

M.config = {
  files_command  = nil,    -- override; list, or function(unrestricted) -> list
  weights = {
    in_buffer       = 60,   -- file is in the buffer list
    adjacent_dir    = 50,   -- multiplied by 0..1 closeness to any open buffer
    recent_access   = 50,   -- exponential decay against access_half_life_s
    recent_mtime    = 5,    -- exponential decay against mtime_half_life_s
    git_dirty       = 8,    -- file is dirty per `git status`
  },
  access_half_life_s = 86400,        -- 1 day
  mtime_half_life_s  = 604800,       -- 1 week
  access_throttle_s  = 5,            -- min seconds between counted accesses
  max_render         = 80,           -- visible rows
  debounce_ms        = 25,           -- filter debounce
  stream_flush_ms    = 30,           -- coalesce streamed chunks
  git_refresh_min_s  = 5,            -- min seconds between git status runs
}

-- ============================================================================
-- Persistent metadata cache
-- ============================================================================

local cache = {}             -- abs_path -> { last_accessed, access_count, mtime, mtime_checked, git_dirty }
local cache_dirty = false
local persist_path = nil

local function get_persist_path()
  if persist_path then return persist_path end
  local dir = vim.fn.stdpath("data") .. "/needle"
  vim.fn.mkdir(dir, "p")
  persist_path = dir .. "/state.json"
  return persist_path
end

local function load_state()
  local f = io.open(get_persist_path(), "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return end
  for path, entry in pairs(data) do
    if type(entry) == "table" then
      cache[path] = {
        last_accessed = tonumber(entry.last_accessed),
        access_count  = tonumber(entry.access_count) or 1,
      }
    end
  end
end

local function save_state()
  if not cache_dirty then return end
  local out = {}
  for path, entry in pairs(cache) do
    if entry.last_accessed then
      out[path] = {
        last_accessed = entry.last_accessed,
        access_count  = entry.access_count,
      }
    end
  end
  local ok, encoded = pcall(vim.json.encode, out)
  if not ok then return end
  local f = io.open(get_persist_path(), "w")
  if not f then return end
  f:write(encoded)
  f:close()
  cache_dirty = false
end

local function record_access(abs_path)
  if not abs_path or abs_path == "" then return end
  if abs_path:match("^%w+://") then return end
  local now = os.time()
  local e = cache[abs_path] or {}
  if e.last_accessed and now - e.last_accessed < M.config.access_throttle_s then return end
  e.last_accessed = now
  e.access_count = (e.access_count or 0) + 1
  cache[abs_path] = e
  cache_dirty = true
end

-- ============================================================================
-- Background metadata refresh
-- ============================================================================

local git_status_inflight = false
local git_status_last = 0

local function refresh_git_status(cwd)
  if git_status_inflight then return end
  if os.time() - git_status_last < M.config.git_refresh_min_s then return end
  git_status_inflight = true
  vim.system({ "git", "-C", cwd, "status", "--porcelain" }, { text = true }, function(result)
    git_status_inflight = false
    git_status_last = os.time()
    if not result or result.code ~= 0 then return end
    local dirty = {}
    for line in (result.stdout or ""):gmatch("[^\n]+") do
      if #line > 3 then
        local fname = line:sub(4)
        if fname:sub(1,1) == '"' then fname = fname:sub(2, -2) end
        local arrow = fname:find(" %-> ")
        if arrow then fname = fname:sub(arrow + 4) end
        dirty[cwd .. "/" .. fname] = true
      end
    end
    vim.schedule(function()
      for path, e in pairs(cache) do
        if e.git_dirty and not dirty[path] then e.git_dirty = false end
      end
      for path in pairs(dirty) do
        local e = cache[path] or {}
        e.git_dirty = true
        cache[path] = e
      end
    end)
  end)
end

local function refresh_visible_mtimes(entries)
  local now = os.time()
  for _, entry in ipairs(entries) do
    local abs = entry.abs
    local c = cache[abs] or {}
    if not c.mtime_checked or now - c.mtime_checked > 60 then
      c.mtime_checked = now
      cache[abs] = c
      uv.fs_stat(abs, function(err, stat)
        if err or not stat then return end
        vim.schedule(function()
          local cur = cache[abs] or {}
          cur.mtime = stat.mtime and stat.mtime.sec or nil
          cache[abs] = cur
        end)
      end)
    end
  end
end

-- Byte value for "/", used by the proximity logic below.
local BSLASH = 47

-- ============================================================================
-- Ranking signals
-- ============================================================================

-- Build (same_dir, ancestor_scores) from the absolute paths of open buffers.
-- For each buffer, the buffer's own directory gets score 1.0 (and is added to
-- `same_dir` for fast same-directory checks). Each strict ancestor `a` of the
-- buffer's directory `d` gets score `depth(a) / depth(d)` -- so siblings score
-- high under deep buffers and lower under shallow ones. Across multiple
-- buffers we keep the per-directory max.
-- Build (same_dir, ancestor_scores) from absolute paths of open buffers,
-- limited to buffers under `cwd`. Depths are measured relative to cwd, so
-- shared ancestors at or above cwd never contribute. For each buffer with
-- cwd-relative dir-depth D, every strict ancestor at cwd-relative depth k
-- (1 <= k < D) gets score k/D, and the buffer's own dir gets 1.0. Across
-- buffers we keep the per-directory max.
local function precompute_proximity(buffer_paths, cwd)
  local same_dir = {}
  local ancestors = {}
  if not cwd or cwd == "" then return same_dir, ancestors end
  local cwd_depth = 0
  for i = 1, #cwd do
    if cwd:byte(i) == BSLASH then cwd_depth = cwd_depth + 1 end
  end
  for _, p in ipairs(buffer_paths) do
    if p ~= "" and not p:match("^%w+://") then
      local dir = vim.fs.dirname(p)
      if dir and dir ~= "" and (dir == cwd or dir:sub(1, #cwd + 1) == cwd .. "/") then
        local total = 0
        for i = 1, #dir do
          if dir:byte(i) == BSLASH then total = total + 1 end
        end
        local buf_depth = total - cwd_depth
        same_dir[dir] = true
        if buf_depth > 0 then
          local seg = 0
          for i = 1, #dir do
            if dir:byte(i) == BSLASH then
              if i > 1 and seg > cwd_depth then
                local prefix = dir:sub(1, i - 1)
                local s = (seg - cwd_depth) / buf_depth
                if s > (ancestors[prefix] or 0) then ancestors[prefix] = s end
              end
              seg = seg + 1
            end
          end
          if (ancestors[dir] or 0) < 1 then ancestors[dir] = 1 end
        end
      end
    end
  end
  return same_dir, ancestors
end

-- Returns closeness in [0, 1]. Same directory as any open buffer => 1.0;
-- otherwise the best (deepest) common ancestor wins, scaled by that buffer's
-- depth via the precomputed `ancestor_scores` map.
-- Returns closeness in [0, 1]. Same directory as any open buffer => 1.0;
-- otherwise we walk the candidate's directory upward (deepest first) and
-- return the first precomputed ancestor score we hit.
local function proximity_score(abs_path, ctx)
  local dir = vim.fs.dirname(abs_path)
  if not dir or dir == "" then return 0 end
  if ctx.same_dir_set[dir] then return 1.0 end
  local s = ctx.ancestor_scores[dir]
  if s then return s end
  for i = #dir, 2, -1 do
    if dir:byte(i) == BSLASH then
      local s2 = ctx.ancestor_scores[dir:sub(1, i - 1)]
      if s2 then return s2 end
    end
  end
  return 0
end

local function decay(now, then_t, half_life)
  if not then_t then return 0 end
  local d = now - then_t
  if d < 0 then return 1 end
  return 0.5 ^ (d / half_life)
end

local function rank_score(abs_path, match_score, proximity, ctx)
  local w = M.config.weights
  local total = match_score
  if ctx.buffer_set[abs_path] then total = total + w.in_buffer end
  total = total + w.adjacent_dir * proximity
  local entry = cache[abs_path]
  if entry then
    if entry.last_accessed then
      total = total + w.recent_access * decay(ctx.now, entry.last_accessed, M.config.access_half_life_s)
    end
    if entry.mtime then
      total = total + w.recent_mtime * decay(ctx.now, entry.mtime, M.config.mtime_half_life_s)
    end
    if entry.git_dirty then total = total + w.git_dirty end
  end
  return total
end

local function build_prefix(abs_path, proximity, ctx)
  local in_buf = ctx.buffer_set[abs_path] == true
  local has_local = proximity > 0
  local entry = cache[abs_path] or {}
  local has_access = entry.last_accessed
    and decay(ctx.now, entry.last_accessed, M.config.access_half_life_s) > 0.1
  local has_mtime = entry.mtime
    and decay(ctx.now, entry.mtime, M.config.mtime_half_life_s) > 0.1
  local has_git = entry.git_dirty == true
  return (in_buf    and "b" or " ")
      .. (has_local and "l" or " ")
      .. (has_access and "a" or " ")
      .. (has_mtime and "m" or " ")
      .. (has_git   and "g" or " ")
      .. " "
end

-- ============================================================================
-- Picker state and rendering
-- ============================================================================

local picker = nil
local NS_HL     = api.nvim_create_namespace("needle_hl")
local NS_PROMPT = api.nvim_create_namespace("needle_prompt")

local schedule_refilter -- forward declaration

local function close_picker()
  if not picker then return end
  pcall(vim.cmd, "stopinsert")
  if picker.discover_kill then pcall(picker.discover_kill) end
  if picker.source and picker.source.cleanup then
    pcall(picker.source.cleanup, picker.source, picker)
  end
  if picker.filter_timer then
    pcall(function() picker.filter_timer:stop() end)
    pcall(function() picker.filter_timer:close() end)
  end
  if picker.flush_timer then
    pcall(function() picker.flush_timer:stop() end)
    pcall(function() picker.flush_timer:close() end)
  end
  if picker.prompt_win and api.nvim_win_is_valid(picker.prompt_win) then
    pcall(api.nvim_win_close, picker.prompt_win, true)
  end
  if picker.results_win and api.nvim_win_is_valid(picker.results_win) then
    pcall(api.nvim_set_current_win, picker.results_win)
    if picker.prev_buf and api.nvim_buf_is_valid(picker.prev_buf) then
      pcall(api.nvim_win_set_buf, picker.results_win, picker.prev_buf)
    end
    if picker.orig_cursorline ~= nil then
      pcall(api.nvim_set_option_value, "cursorline", picker.orig_cursorline, { win = picker.results_win })
    end
    if picker.orig_wrap ~= nil then
      pcall(api.nvim_set_option_value, "wrap", picker.orig_wrap, { win = picker.results_win })
    end
  end
  if picker.prompt_buf and api.nvim_buf_is_valid(picker.prompt_buf) then
    pcall(api.nvim_buf_delete, picker.prompt_buf, { force = true })
  end
  picker = nil
  save_state()
end

local function compute_filtered()
  if not picker then return {} end
  return picker.source:filter(picker)
end

local function update_title()
  if not picker or not api.nvim_win_is_valid(picker.prompt_win) then return end
  local entries = picker.filtered or {}
  local title = string.format(" needle %s %d/%d",
    picker.source:title(), #entries, #picker.candidates)
  local escaped = title:gsub("%%", "%%%%")
  pcall(api.nvim_set_option_value, "winbar", escaped, { win = picker.prompt_win })
end

local function render_results()
  if not picker or not api.nvim_buf_is_valid(picker.results_buf) then return end
  local entries = picker.filtered
  local lines = {}
  for i = 1, #entries do
    lines[i] = (entries[i].prefix or "") .. (entries[i].text or "")
  end
  if #lines == 0 then lines = { "" } end

  api.nvim_set_option_value("modifiable", true, { buf = picker.results_buf })
  api.nvim_buf_set_lines(picker.results_buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(picker.results_buf, NS_HL, 0, -1)

  for i, e in ipairs(entries) do
    local prefix_len = e.prefix and #e.prefix or 0
    if prefix_len > 0 then
      api.nvim_buf_set_extmark(picker.results_buf, NS_HL, i - 1, 0, {
        end_col = prefix_len,
        hl_group = "NeedleSignal",
      })
    end
    if e.positions then
      for _, pos in ipairs(e.positions) do
        api.nvim_buf_set_extmark(picker.results_buf, NS_HL, i - 1, pos - 1 + prefix_len, {
          end_col = pos + prefix_len,
          hl_group = "NeedleMatch",
        })
      end
    end
  end

  picker.selected = math.max(1, math.min(picker.selected or 1, math.max(1, #entries)))
  if #entries > 0 then
    api.nvim_buf_set_extmark(picker.results_buf, NS_HL, picker.selected - 1, 0, {
      end_row = picker.selected,
      hl_group = "NeedleSel",
      hl_eol = true,
      priority = 200,
    })
  end
  api.nvim_set_option_value("modifiable", false, { buf = picker.results_buf })

  if api.nvim_win_is_valid(picker.results_win) and #entries > 0 then
    pcall(api.nvim_win_set_cursor, picker.results_win, { picker.selected, 0 })
  end

  update_title()

  if picker.source.after_render then picker.source:after_render(picker) end
end

local function refilter_now()
  if not picker then return end
  picker.filtered = compute_filtered()
  render_results()
end

schedule_refilter = function()
  if not picker then return end
  if not picker.filter_timer then picker.filter_timer = uv.new_timer() end
  picker.filter_timer:stop()
  picker.filter_timer:start(M.config.debounce_ms, 0, vim.schedule_wrap(function()
    if picker then refilter_now() end
  end))
end

-- ============================================================================
-- UI: floating windows + keymaps
-- ============================================================================

local function open_windows()
  -- If the current window isn't full height (something above or below it),
  -- or is a floating window (not part of the main layout), create a new
  -- full-height vertical split (with an empty buffer) so the picker doesn't
  -- squash into a partial pane. The empty buffer becomes the "previous"
  -- state we restore to when the picker closes.
  local is_floating = api.nvim_win_get_config(0).relative ~= ""
  if is_floating
    or vim.fn.winnr("k") ~= vim.fn.winnr()
    or vim.fn.winnr("j") ~= vim.fn.winnr()
  then
    vim.cmd("botright vsplit | enew")
  end

  local results_win = api.nvim_get_current_win()
  local prev_buf = api.nvim_win_get_buf(results_win)
  local orig_cursorline = api.nvim_get_option_value("cursorline", { win = results_win })
  local orig_wrap = api.nvim_get_option_value("wrap", { win = results_win })

  local results_buf = api.nvim_create_buf(false, true)
  local prompt_buf  = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = results_buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = prompt_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = results_buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = prompt_buf })
  api.nvim_set_option_value("filetype", "needle", { buf = results_buf })
  api.nvim_set_option_value("filetype", "needle", { buf = prompt_buf })

  api.nvim_win_set_buf(results_win, results_buf)
  api.nvim_set_option_value("cursorline", false, { win = results_win })
  api.nvim_set_option_value("wrap", false, { win = results_win })

  -- Split results_win, placing a 1-row tall prompt window above.
  vim.cmd("aboveleft 1split")
  local prompt_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(prompt_win, prompt_buf)
  api.nvim_win_set_height(prompt_win, 1)
  api.nvim_set_option_value("winfixheight", true, { win = prompt_win })
  api.nvim_set_option_value("number",         false, { win = prompt_win })
  api.nvim_set_option_value("relativenumber", false, { win = prompt_win })
  api.nvim_set_option_value("signcolumn",     "no",  { win = prompt_win })
  api.nvim_set_option_value("cursorline",     false, { win = prompt_win })
  api.nvim_set_option_value("wrap",           false, { win = prompt_win })
  api.nvim_set_option_value("winbar",         " needle ", { win = prompt_win })

  api.nvim_buf_set_extmark(prompt_buf, NS_PROMPT, 0, 0, {
    virt_text = { { "🔍 ", "Special" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })
  return prompt_buf, prompt_win, results_buf, results_win, prev_buf, orig_cursorline, orig_wrap
end

local function move_selection(delta)
  if not picker then return end
  local n = #picker.filtered
  if n == 0 then return end
  picker.selected = ((picker.selected - 1 + delta) % n) + 1
  render_results()
end

local function accept_selection(open_cmd)
  if not picker or #picker.filtered == 0 then close_picker(); return end
  local entry = picker.filtered[picker.selected]
  local source = picker.source
  -- Capture the target window before tearing down the picker, and use
  -- `nvim_win_call` below so the :edit runs there regardless of focus changes
  -- (e.g. a floating notification stealing focus between teardown and accept).
  local target_win = picker.results_win
  close_picker()
  vim.schedule(function()
    if target_win and api.nvim_win_is_valid(target_win) then
      api.nvim_win_call(target_win, function()
        source:accept(entry, open_cmd)
      end)
    else
      source:accept(entry, open_cmd)
    end
  end)
end

local function map_keys(buf, modes, lhs, fn)
  for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
    api.nvim_buf_set_keymap(buf, mode, lhs, "", {
      noremap = true, silent = true, callback = fn,
    })
  end
end

local function setup_keymaps(prompt_buf)
  map_keys(prompt_buf, "n", "<Esc>", close_picker)
  map_keys(prompt_buf, {"i","n"}, "<C-c>",  close_picker)
  map_keys(prompt_buf, {"i","n"}, "<C-n>",  function() move_selection(1)  end)
  map_keys(prompt_buf, {"i","n"}, "<Down>", function() move_selection(1)  end)
  map_keys(prompt_buf, {"i","n"}, "<C-j>",  function() move_selection(1)  end)
  map_keys(prompt_buf, {"i","n"}, "<C-p>",  function() move_selection(-1) end)
  map_keys(prompt_buf, {"i","n"}, "<Up>",   function() move_selection(-1) end)
  map_keys(prompt_buf, {"i","n"}, "<C-k>",  function() move_selection(-1) end)
  map_keys(prompt_buf, {"i","n"}, "<C-d>",  function() move_selection(10)  end)
  map_keys(prompt_buf, {"i","n"}, "<C-u>",  function() move_selection(-10) end)
  map_keys(prompt_buf, {"i","n"}, "<CR>",   function() accept_selection("edit")    end)
  map_keys(prompt_buf, {"i","n"}, "<C-x>",  function() accept_selection("split")   end)
  map_keys(prompt_buf, {"i","n"}, "<C-v>",  function() accept_selection("vsplit")  end)
  map_keys(prompt_buf, {"i","n"}, "<C-t>",  function() accept_selection("tabedit") end)
end

local function gather_buffer_set()
  local set = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and api.nvim_get_option_value("buflisted", { buf = b }) then
      local name = api.nvim_buf_get_name(b)
      if name ~= "" then set[name] = true end
    end
  end
  return set
end


-- ============================================================================
-- Sources
-- ============================================================================

-- Streams a process's stdout line by line into picker.candidates and triggers
-- coalesced refilters. Returns a kill function.
local function stream_lines_into_picker(cmd, cwd, on_done)
  if not picker then return function() end end
  picker.discover_epoch = (picker.discover_epoch or 0) + 1
  local epoch = picker.discover_epoch
  local line_buf = ""
  local sys_obj = vim.system(cmd, {
    cwd = cwd,
    text = true,
    stdout = function(err, data)
      if err or not data then return end
      vim.schedule(function()
        if not picker or picker.discover_epoch ~= epoch then return end
        line_buf = line_buf .. data
        local cands = picker.candidates
        while true do
          local nl = line_buf:find("\n", 1, true)
          if not nl then break end
          local rel = line_buf:sub(1, nl - 1)
          line_buf = line_buf:sub(nl + 1)
          if rel:sub(1, 2) == "./" then rel = rel:sub(3) end
          if rel ~= "" then cands[#cands + 1] = rel end
        end
        if not picker.flush_timer then picker.flush_timer = uv.new_timer() end
        picker.flush_timer:stop()
        picker.flush_timer:start(M.config.stream_flush_ms, 0, vim.schedule_wrap(function()
          if picker then schedule_refilter() end
        end))
      end)
    end,
  }, function(_)
    vim.schedule(function()
      if not picker or picker.discover_epoch ~= epoch then return end
      if line_buf ~= "" then
        local rel = line_buf
        line_buf = ""
        if rel:sub(1, 2) == "./" then rel = rel:sub(3) end
        if rel ~= "" then picker.candidates[#picker.candidates + 1] = rel end
      end
      schedule_refilter()
      if on_done then on_done() end
    end)
  end)
  return function() pcall(function() sys_obj:kill("sigterm") end) end
end

-- When `opts_cwd` is provided we use it as-is. Otherwise we pick a search root
-- based on the current buffer: prefer cwd if the buffer lives under it, then
-- the nearest git root walking up from the buffer's directory, and finally the
-- buffer's own directory.
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
  -- The buffer may point at a dead/nonexistent path (e.g. a deleted file), in
  -- which case buf_dir is empty or missing on disk; fall back to cwd so we
  -- never hand vim.system an invalid working directory.
  if not buf_dir or buf_dir == "" or vim.fn.isdirectory(buf_dir) == 0 then
    return current_cwd
  end
  -- Prefer the buffer's git worktree root. `git rev-parse --show-toplevel`
  -- reports the worktree root, which is what we want even when launched at a
  -- parent dir holding several worktrees: a plain `.git` upward walk would land
  -- on a bare repo's directory rather than the worktree.
  local toplevel = vim.fn.systemlist({ "git", "-C", buf_dir, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and toplevel[1] and toplevel[1] ~= "" then
    return toplevel[1]
  end
  -- Not in a git repo: fall back to cwd when the buffer lives under it, else
  -- search the buffer's own directory.
  if buf_dir == current_cwd or buf_dir:sub(1, #current_cwd + 1) == current_cwd .. "/" then
    return current_cwd
  end
  return buf_dir
end

-- ----------------------------------------------------------------------------
-- Files source: signal-aware file picker (fd/rg/find driven).
-- ----------------------------------------------------------------------------
local FilesSource = {}
FilesSource.__index = FilesSource

function FilesSource.new(opts)
  opts = opts or {}
  local self = setmetatable({
    cwd = nil,                  -- resolved lazily; see cwd_future
    unrestricted = opts.unrestricted == true,
    buffer_set = {},
    same_dir_set = {},
    ancestor_scores = {},
  }, FilesSource)

  -- The `.git` upward walk is the slow part of startup, so resolve the search
  -- root off the path that paints the UI. Capture the originating buffer name
  -- now (cheap) since the picker's own buffer is focused by the time we run.
  local origin_buf_name = api.nvim_buf_get_name(api.nvim_get_current_buf())
  self.cwd_future = Future.new(function(resolve)
    vim.schedule(function()
      local cwd = discover_search_dir(opts.cwd, origin_buf_name)
      self.cwd = cwd
      self.buffer_set = gather_buffer_set()
      local buffer_paths = {}
      for path in pairs(self.buffer_set) do buffer_paths[#buffer_paths + 1] = path end
      self.same_dir_set, self.ancestor_scores =
        precompute_proximity(buffer_paths, cwd)
      refresh_git_status(cwd)
      update_title()
      resolve(cwd)
    end)
  end)
  return self
end

function FilesSource:title()
  if not self.cwd then return "files [resolving…]" end
  local d = vim.fn.fnamemodify(self.cwd, ":~")
  return string.format("files [%s]%s", d, self.unrestricted and " (unrestricted)" or "")
end

function FilesSource:_command()
  if M.config.files_command then
    if type(M.config.files_command) == "function" then
      return M.config.files_command(self.unrestricted)
    end
    return M.config.files_command
  end
  return default_files_command(self.unrestricted)
end

function FilesSource:discover(p)
  local killed, inner_kill = false, nil
  self.cwd_future:get(function(cwd)
    if killed or not picker or picker ~= p then return end
    inner_kill = stream_lines_into_picker(self:_command(), cwd)
  end)
  return function()
    killed = true
    if inner_kill then inner_kill() end
  end
end

function FilesSource:filter(p)
  local prompt = p.prompt
  local cands  = p.candidates
  local cwd    = self.cwd
  local ctx = {
    now             = os.time(),
    same_dir_set    = self.same_dir_set,
    ancestor_scores = self.ancestor_scores,
    buffer_set      = self.buffer_set,
  }
  local results = {}
  if prompt == "" then
    for i = 1, #cands do
      local pp = cands[i]
      local abs = cwd .. "/" .. pp
      local prox = proximity_score(abs, ctx)
      results[#results + 1] = {
        score = rank_score(abs, 0, prox, ctx),
        text = pp, abs = abs, proximity = prox,
      }
    end
  else
    local p_lower = prompt:lower()
    for i = 1, #cands do
      local pp = cands[i]
      local h_lower = pp:lower()
      local ms, positions = score.score_match(prompt, p_lower, pp, h_lower)
      if ms then
        local abs = cwd .. "/" .. pp
        local prox = proximity_score(abs, ctx)
        results[#results + 1] = {
          score = rank_score(abs, ms, prox, ctx),
          text = pp, abs = abs, positions = positions, proximity = prox,
        }
      end
    end
  end
  table.sort(results, function(a, b) return a.score > b.score end)
  local max = M.config.max_render
  if #results > max then
    for i = max + 1, #results do results[i] = nil end
  end
  for i = 1, #results do
    results[i].prefix = build_prefix(results[i].abs, results[i].proximity, ctx)
  end
  return results
end

function FilesSource:after_render(_)
  refresh_visible_mtimes(picker and picker.filtered or {})
end

function FilesSource:accept(entry, open_cmd)
  record_access(entry.abs)
  vim.cmd((open_cmd or "edit") .. " " .. vim.fn.fnameescape(entry.abs))
end

function FilesSource:keymaps(p)
  map_keys(p.prompt_buf, {"i","n"}, "<C-h>", function()
    self.unrestricted = not self.unrestricted
    if p.discover_kill then pcall(p.discover_kill) end
    p.candidates = {}
    p.filtered = {}
    p.discover_kill = self:discover(p)
    schedule_refilter()
    update_title()
  end)
end

-- ----------------------------------------------------------------------------
-- Buffers source: list of open buffers, ranked by recent use.
-- ----------------------------------------------------------------------------
local BuffersSource = {}
BuffersSource.__index = BuffersSource

function BuffersSource.new(_)
  return setmetatable({}, BuffersSource)
end

function BuffersSource:title() return "buffers" end

function BuffersSource:discover(p)
  local infos = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(infos, function(a, b) return (a.lastused or 0) > (b.lastused or 0) end)
  local cwd = vim.fn.getcwd()
  local current = api.nvim_get_current_buf()
  for _, info in ipairs(infos) do
    if info.name and info.name ~= "" and info.bufnr ~= current then
      p.candidates[#p.candidates + 1] = { name = info.name, cwd = cwd }
    end
  end
  return function() end
end

function BuffersSource:filter(p)
  local prompt = p.prompt
  local cands = p.candidates
  local results = {}
  if prompt == "" then
    for i = 1, #cands do
      local c = cands[i]
      local display = (c.name:sub(1, #c.cwd + 1) == c.cwd .. "/")
        and c.name:sub(#c.cwd + 2) or c.name
      results[#results + 1] = { score = -i, text = display, abs = c.name }
    end
  else
    local p_lower = prompt:lower()
    for i = 1, #cands do
      local c = cands[i]
      local display = (c.name:sub(1, #c.cwd + 1) == c.cwd .. "/")
        and c.name:sub(#c.cwd + 2) or c.name
      local ms, positions = score.score_match(prompt, p_lower, display, display:lower())
      if ms then
        results[#results + 1] = {
          score = ms - i * 0.01,
          text = display, abs = c.name, positions = positions,
        }
      end
    end
  end
  table.sort(results, function(a, b) return a.score > b.score end)
  local max = M.config.max_render
  if #results > max then
    for i = max + 1, #results do results[i] = nil end
  end
  return results
end

function BuffersSource:accept(entry, open_cmd)
  record_access(entry.abs)
  vim.cmd((open_cmd or "edit") .. " " .. vim.fn.fnameescape(entry.abs))
end

-- ----------------------------------------------------------------------------
-- Help source: completion-driven help tag picker.
-- ----------------------------------------------------------------------------
local HelpSource = {}
HelpSource.__index = HelpSource

function HelpSource.new(_)
  return setmetatable({}, HelpSource)
end

function HelpSource:title() return "help" end

function HelpSource:discover(p)
  vim.schedule(function()
    if not picker then return end
    local seen = {}
    local files = api.nvim_get_runtime_file("doc/tags", true)
    for _, extra in ipairs(api.nvim_get_runtime_file("doc/tags-*", true)) do
      files[#files + 1] = extra
    end
    for _, path in ipairs(files) do
      local f = io.open(path, "r")
      if f then
        for line in f:lines() do
          local tag = line:match("^([^\t]+)\t")
          if tag and not seen[tag] then
            seen[tag] = true
            p.candidates[#p.candidates + 1] = tag
          end
        end
        f:close()
      end
    end
    schedule_refilter()
  end)
  return function() end
end

function HelpSource:filter(p)
  local prompt = p.prompt
  local cands = p.candidates
  local results = {}
  if prompt == "" then
    local n = math.min(M.config.max_render, #cands)
    for i = 1, n do
      results[#results + 1] = { score = -i, text = cands[i] }
    end
    return results
  end
  local p_lower = prompt:lower()
  for i = 1, #cands do
    local pp = cands[i]
    local ms, positions = score.score_match(prompt, p_lower, pp, pp:lower())
    if ms then
      results[#results + 1] = { score = ms, text = pp, positions = positions }
    end
  end
  table.sort(results, function(a, b) return a.score > b.score end)
  local max = M.config.max_render
  if #results > max then
    for i = max + 1, #results do results[i] = nil end
  end
  return results
end

function HelpSource:accept(entry, _)
  vim.cmd("help " .. vim.fn.fnameescape(entry.text))
end


-- ============================================================================
-- Public API
-- ============================================================================

local function open_with_source(source)
  if picker then close_picker() end
  local prompt_buf, prompt_win, results_buf, results_win, prev_buf, orig_cursorline, orig_wrap = open_windows()

  picker = {
    source          = source,
    candidates      = {},
    filtered        = {},
    prompt          = "",
    selected        = 1,
    prompt_buf      = prompt_buf,
    prompt_win      = prompt_win,
    results_buf     = results_buf,
    results_win     = results_win,
    prev_buf        = prev_buf,
    orig_cursorline = orig_cursorline,
    orig_wrap       = orig_wrap,
  }

  api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt_buf,
    callback = function()
      if not picker then return end
      local lines = api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
      picker.prompt = lines[1] or ""
      picker.selected = 1
      if source.on_prompt_change then source:on_prompt_change(picker) end
      schedule_refilter()
    end,
  })

  api.nvim_create_autocmd("WinClosed", {
    pattern = { tostring(prompt_win), tostring(results_win) },
    callback = function() vim.schedule(close_picker) end,
  })

  setup_keymaps(prompt_buf)
  if source.keymaps then source:keymaps(picker) end
  vim.cmd("startinsert!")

  -- Paint the (empty) UI now; defer discovery so the prompt is interactive
  -- immediately, before any source setup (e.g. resolving the search root).
  refilter_now()
  vim.schedule(function()
    if not picker or picker.source ~= source then return end
    picker.discover_kill = source:discover(picker)
    refilter_now()
  end)
end

function M.files(opts)   open_with_source(FilesSource.new(opts))   end
function M.buffers(opts) open_with_source(BuffersSource.new(opts)) end
function M.help(opts)    open_with_source(HelpSource.new(opts))    end

-- Backward compat
function M.open(opts) M.files(opts) end

function M.toggle(opts)
  if picker then close_picker() else M.files(opts) end
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  load_state()

  api.nvim_set_hl(0, "NeedleMatch",  { link = "Special",  default = true })
  api.nvim_set_hl(0, "NeedleSel",    { link = "PmenuSel", default = true })
  api.nvim_set_hl(0, "NeedleSignal", { link = "Comment",  default = true })

  api.nvim_create_autocmd("BufWinEnter", {
    callback = function(ev)
      local name = api.nvim_buf_get_name(ev.buf)
      if name ~= "" and not name:match("^%w+://") then
        record_access(name)
      end
    end,
  })

  api.nvim_create_autocmd("VimLeavePre", { callback = save_state })

  api.nvim_create_user_command("Needle", function(o)
    M.files({ cwd = (o.args ~= "" and vim.fn.expand(o.args)) or nil })
  end, { nargs = "?", complete = "dir" })
  api.nvim_create_user_command("NeedleBuffers", function() M.buffers() end, {})
  api.nvim_create_user_command("NeedleHelp", function() M.help() end, {})
end

return M
