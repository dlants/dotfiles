-- glean: review the diff between two git refs in a single foldable buffer.
--
-- The model (FileEntries / Commits from glean.git, overlaid with the persisted
-- ReviewStore from glean.state) is the single source of truth; the buffer is a
-- pure projection of it. A parallel `row_map[row]` resolves any cursor row back
-- to its commit/file/hunk/line so actions can act on the semantic target.
--
-- Two scopes share one review store:
--   - "combined": the net diff base...target (Stage 2; seen overlay is Stage 4).
--   - "commits": every commit laid out flat, the natural place seen marks and
--     comments are *authored* against a stable (commit_sha, path, new_lnum).
--
-- Collapse is ephemeral session view-state: it is initialized from seen status
-- when a scope is (re)built, then evolves independently and is never persisted.
local git_mod = require("glean.git")
local state_mod = require("glean.state")
local M = {}
local api = vim.api
local NS = api.nvim_create_namespace("glean_hl")
local COMMENT_NS = api.nvim_create_namespace("glean_comments")

M.config = {
  default_base = "main",
}

local Session = {}
Session.__index = Session

local CHEVRON_OPEN = "▾"
local CHEVRON_CLOSED = "▸"

-- The new-file line range a hunk introduces, or nil for a pure-deletion hunk
-- (new_count == 0) which addresses no new-file line.
local function hunk_new_range(hunk)
  if hunk.new_count and hunk.new_count > 0 then
    return { hunk.new_start, hunk.new_start + hunk.new_count - 1 }
  end
  return nil
end

-- All new-file ranges a file changes within one commit's diff.
local function file_new_ranges(file)
  local ranges = {}
  for _, hunk in ipairs(file.hunks) do
    local r = hunk_new_range(hunk)
    if r then ranges[#ranges + 1] = r end
  end
  return ranges
end

-- Is a file fully seen for (sha, path)? (every changed new-file range covered)
local function file_seen(store, sha, path, file)
  local seen = store:seen_ranges(sha, path)
  for _, r in ipairs(file_new_ranges(file)) do
    if not state_mod.range_covered(seen, r) then return false end
  end
  return true
end

-- Is a whole commit fully seen?
local function commit_seen(store, commit)
  for _, file in ipairs(commit.files) do
    if not file_seen(store, commit.sha, file.path, file) then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Build (pure projection): returns lines, row_map, highlights, comments.
-- ---------------------------------------------------------------------------

function Session:build()
  local lines = {}
  local row_map = {}
  local highlights = {}
  local comments = {}
  local function emit(text, target, hl)
    lines[#lines + 1] = text
    local row = #lines - 1
    row_map[row] = target
    if hl then highlights[#highlights + 1] = { row = row, hl = hl } end
    return row
  end

  local function emit_file_body(commit_sha, fi, file, target_base)
    for hi, hunk in ipairs(file.hunks) do
      local target = vim.tbl_extend("force", target_base, { hunk = hi })
      emit(hunk.header, target, "GleanHunkHeader")
      for li, dl in ipairs(hunk.lines) do
        local marker = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
        local hl = dl.kind == "add" and "GleanAdd"
          or dl.kind == "del" and "GleanDel"
          or "GleanContext"
        if commit_sha and dl.new_lnum
          and state_mod.covers(self.store:seen_ranges(commit_sha, file.path), dl.new_lnum) then
          hl = "GleanSeen"
        end
        local row = emit(marker .. dl.text,
          vim.tbl_extend("force", target, { line = li }), hl)
        if commit_sha and dl.new_lnum then
          local texts = self.store:comments_at(commit_sha, file.path, dl.new_lnum)
          if #texts > 0 then comments[#comments + 1] = { row = row, texts = texts } end
        end
      end
    end
  end

  if self.scope == "commits" then
    for ci, commit in ipairs(self.commits) do
      local chevron = commit.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
      local mark = commit_seen(self.store, commit) and "✓" or "●"
      local short = commit.sha:sub(1, 8)
      emit(("%s %s %s %s"):format(chevron, mark, short, commit.summary),
        { commit = ci }, "GleanCommitHeader")
      if not commit.collapsed then
        for fi, file in ipairs(commit.files) do
          local fchev = file.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
          local fmark = file_seen(self.store, commit.sha, file.path, file) and "✓" or " "
          local kind = file.kind and (" [" .. file.kind .. "]") or ""
          emit(("  %s %s %s%s"):format(fchev, fmark, file.path, kind),
            { commit = ci, file = fi }, "GleanFileHeader")
          if not file.collapsed then
            emit_file_body(commit.sha, fi, file, { commit = ci, file = fi })
          end
        end
      end
    end
  else
    for fi, file in ipairs(self.files) do
      local chevron = file.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
      local kind = file.kind and (" [" .. file.kind .. "]") or ""
      emit(chevron .. " " .. file.path .. kind, { file = fi }, "GleanFileHeader")
      if not file.collapsed then
        emit_file_body(nil, fi, file, { file = fi })
      end
    end
  end

  return lines, row_map, highlights, comments
end

function Session:render()
  local lines, row_map, highlights, comments = self:build()
  self.row_map = row_map
  local win = self.win
  local cur
  if win and api.nvim_win_is_valid(win) then
    cur = api.nvim_win_get_cursor(win)
  end
  api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = self.buf })
  api.nvim_buf_clear_namespace(self.buf, NS, 0, -1)
  for _, hl in ipairs(highlights) do
    api.nvim_buf_set_extmark(self.buf, NS, hl.row, 0, {
      end_row = hl.row + 1,
      end_col = 0,
      hl_group = hl.hl,
      hl_eol = true,
    })
  end
  api.nvim_buf_clear_namespace(self.buf, COMMENT_NS, 0, -1)
  for _, c in ipairs(comments) do
    local virt_lines = {}
    for _, t in ipairs(c.texts) do
      virt_lines[#virt_lines + 1] = { { "    💬 " .. t.text, "GleanComment" } }
    end
    api.nvim_buf_set_extmark(self.buf, COMMENT_NS, c.row, 0, {
      virt_lines = virt_lines,
    })
  end
  if cur then
    local last = math.max(1, #lines)
    cur[1] = math.min(cur[1], last)
    pcall(api.nvim_win_set_cursor, win, cur)
  end
end

-- ---------------------------------------------------------------------------
-- Collapse (ephemeral) — initialized from seen, then independent.
-- ---------------------------------------------------------------------------

-- (Re)initialize commit-scope collapse from seen status: fully-seen commits and
-- files start collapsed so only unseen work is expanded. Never persisted.
function Session:init_collapse()
  for _, commit in ipairs(self.commits) do
    commit.collapsed = commit_seen(self.store, commit)
    for _, file in ipairs(commit.files) do
      file.collapsed = file_seen(self.store, commit.sha, file.path, file)
    end
  end
end

function Session:cursor_row()
  if self.win and api.nvim_win_is_valid(self.win) then
    return api.nvim_win_get_cursor(self.win)[1] - 1
  end
  return 0
end

function Session:toggle_collapse(row)
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  if not target then return end
  if self.scope == "commits" then
    local commit = self.commits[target.commit]
    if target.file then
      commit.files[target.file].collapsed = not commit.files[target.file].collapsed
    else
      commit.collapsed = not commit.collapsed
    end
  else
    if target.file then
      self.files[target.file].collapsed = not self.files[target.file].collapsed
    end
  end
  self:render()
end

-- ---------------------------------------------------------------------------
-- Seen marks (commit scope) — authored against (commit_sha, path, new range).
-- ---------------------------------------------------------------------------

-- The (commit_sha, path, range) tuples a target row addresses. A commit header
-- yields every file's changed ranges; a file header yields that file's ranges;
-- a hunk/line yields that hunk's range.
function Session:target_ranges(target)
  local commit = self.commits[target.commit]
  local out = {}
  if target.file then
    local file = commit.files[target.file]
    if target.hunk then
      local r = hunk_new_range(file.hunks[target.hunk])
      if r then out[#out + 1] = { sha = commit.sha, path = file.path, range = r } end
    else
      for _, r in ipairs(file_new_ranges(file)) do
        out[#out + 1] = { sha = commit.sha, path = file.path, range = r }
      end
    end
  else
    for _, file in ipairs(commit.files) do
      for _, r in ipairs(file_new_ranges(file)) do
        out[#out + 1] = { sha = commit.sha, path = file.path, range = r }
      end
    end
  end
  return out
end

-- Toggle seen on the cursor's target: if every addressed range is already seen,
-- unmark them; otherwise mark them all. Persists the affected commit shards.
function Session:toggle_seen(row)
  if self.scope ~= "commits" then return end
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  if not target or not target.commit then return end
  local tuples = self:target_ranges(target)
  if #tuples == 0 then return end
  local all_seen = true
  for _, t in ipairs(tuples) do
    if not state_mod.range_covered(self.store:seen_ranges(t.sha, t.path), t.range) then
      all_seen = false
      break
    end
  end
  local touched = {}
  for _, t in ipairs(tuples) do
    if all_seen then
      self.store:unmark_seen(t.sha, t.path, t.range)
    else
      self.store:mark_seen(t.sha, t.path, t.range)
    end
    touched[t.sha] = true
  end
  for sha in pairs(touched) do self.store:save_commit(sha) end
  self:render()
end

-- Mark a visual span of diff rows seen: translate each row's diff line to its
-- new_lnum, group by (commit, path), and store exactly those ranges (sub-hunk).
-- Deletion-only rows contribute no new-file line and are skipped.
function Session:mark_visual_range(srow, erow)
  if self.scope ~= "commits" then return end
  if srow > erow then srow, erow = erow, srow end
  local groups = {}
  for row = srow, erow do
    local target = self.row_map[row]
    if target and target.commit and target.file and target.line then
      local commit = self.commits[target.commit]
      local file = commit.files[target.file]
      local dl = file.hunks[target.hunk].lines[target.line]
      if dl.new_lnum then
        local key = commit.sha .. "\0" .. file.path
        groups[key] = groups[key] or { sha = commit.sha, path = file.path, lnums = {} }
        groups[key].lnums[#groups[key].lnums + 1] = dl.new_lnum
      end
    end
  end
  local touched = {}
  for _, g in pairs(groups) do
    for _, l in ipairs(g.lnums) do
      self.store:mark_seen(g.sha, g.path, { l, l })
    end
    touched[g.sha] = true
  end
  for sha in pairs(touched) do self.store:save_commit(sha) end
  self:render()
end

-- ---------------------------------------------------------------------------
-- Comments (commit scope) — anchored to (commit_sha, path, new_lnum).
-- ---------------------------------------------------------------------------

-- Resolve a row to (sha, path, new_lnum). A deletion row (no new_lnum) anchors
-- to the nearest surviving new-file line in its hunk.
function Session:comment_anchor(row)
  local target = self.row_map[row]
  if not target or not target.commit or not target.line then return nil end
  local commit = self.commits[target.commit]
  local file = commit.files[target.file]
  local hunk = file.hunks[target.hunk]
  local dl = hunk.lines[target.line]
  local lnum = dl.new_lnum
  if not lnum then
    for li = target.line, #hunk.lines do
      if hunk.lines[li].new_lnum then lnum = hunk.lines[li].new_lnum break end
    end
  end
  if not lnum then
    for li = target.line, 1, -1 do
      if hunk.lines[li].new_lnum then lnum = hunk.lines[li].new_lnum break end
    end
  end
  if not lnum then return nil end
  return commit.sha, file.path, lnum
end

function Session:add_comment_at(row, text)
  if self.scope ~= "commits" then return end
  if row == nil then row = self:cursor_row() end
  if not text or text == "" then return end
  local sha, path, lnum = self:comment_anchor(row)
  if not sha then return end
  self.store:add_comment(sha, path, lnum, text)
  self.store:save_commit(sha)
  self:render()
end

-- ---------------------------------------------------------------------------
-- Scope switching.
-- ---------------------------------------------------------------------------

function Session:set_scope(scope)
  if scope == self.scope then return end
  self.scope = scope
  if scope == "commits" then self:init_collapse() end
  self:render()
end

function Session:toggle_scope()
  self:set_scope(self.scope == "commits" and "combined" or "commits")
end

-- ---------------------------------------------------------------------------
-- Keymaps / open.
-- ---------------------------------------------------------------------------

local function setup_keymaps(buf, session)
  local function map(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("n", "=", function() session:toggle_collapse() end)
  map("n", "m", function() session:toggle_seen() end)
  map("x", "m", function()
    local srow = vim.fn.getpos("v")[2] - 1
    local erow = vim.fn.getpos(".")[2] - 1
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    session:mark_visual_range(srow, erow)
  end)
  map("n", "c", function()
    vim.ui.input({ prompt = "glean comment: " }, function(text)
      if text then session:add_comment_at(nil, text) end
    end)
  end)
  map("n", "S", function() session:toggle_scope() end)
  map("n", "q", function()
    if api.nvim_win_is_valid(session.win) then
      api.nvim_win_close(session.win, true)
    end
  end)
end

-- Open a review of `base...target`. `opts`:
--   - base, target (required): refs to diff.
--   - repo_root, run (optional): injected for tests.
--   - scope (optional, default "combined").
--   - state_dir (optional): override the ReviewStore directory (tests).
--   - open_window (optional, default true).
function M.open(opts)
  assert(opts and opts.base and opts.target, "glean.open requires base and target")
  local repo_root = opts.repo_root
    or git_mod.discover_repo_root(api.nvim_buf_get_name(0))
  assert(repo_root, "glean: could not find a git repo root")
  local git = git_mod.new({ repo_root = repo_root, run = opts.run })

  local files, err = git:combined_diff(opts.base, opts.target)
  if not files then error("glean: combined_diff failed: " .. tostring(err)) end
  for _, f in ipairs(files) do f.collapsed = false end

  local commit_list, cerr = git:commits(opts.base, opts.target)
  if not commit_list then error("glean: commits failed: " .. tostring(cerr)) end
  local shas = {}
  for _, c in ipairs(commit_list) do
    c.files = git:commit_diff(c.sha) or {}
    shas[#shas + 1] = c.sha
  end

  local store = state_mod.new({ dir = opts.state_dir })
  store:load(shas)

  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_set_option_value("filetype", "glean", { buf = buf })
  pcall(api.nvim_buf_set_name, buf, "glean://" .. buf .. ":" .. opts.base .. "..." .. opts.target)

  local session = setmetatable({
    git = git,
    store = store,
    base = opts.base,
    target = opts.target,
    files = files,
    commits = commit_list,
    scope = opts.scope or "combined",
    buf = buf,
    win = nil,
    row_map = {},
  }, Session)
  session:init_collapse()

  local open_window = opts.open_window ~= false
  if open_window then
    vim.cmd("tabnew")
    session.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(session.win, buf)
    setup_keymaps(buf, session)
  end

  session:render()
  return session
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  api.nvim_set_hl(0, "GleanFileHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanCommitHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanHunkHeader", { link = "Comment", default = true })
  api.nvim_set_hl(0, "GleanAdd", { link = "DiffAdd", default = true })
  api.nvim_set_hl(0, "GleanDel", { link = "DiffDelete", default = true })
  api.nvim_set_hl(0, "GleanContext", { link = "Normal", default = true })
  api.nvim_set_hl(0, "GleanSeen", { link = "Comment", default = true })
  api.nvim_set_hl(0, "GleanComment", { link = "WarningMsg", default = true })
  api.nvim_create_user_command("Glean", function(o)
    local args = o.fargs
    local base = args[1] or M.config.default_base
    local target = args[2] or "HEAD"
    M.open({ base = base, target = target })
  end, { nargs = "*" })
end

return M
