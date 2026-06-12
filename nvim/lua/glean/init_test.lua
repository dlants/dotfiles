-- Tier 3a tests for glean.init: render the combined scope against a hermetic
-- git fixture and assert observable buffer state, row_map, and collapse
-- re-render. Run with:
--   nvim -l nvim/lua/glean/init_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local glean = require("glean.init")
local testutil = require("glean.testutil")
local h = testutil.new()
local api = vim.api

local repo = testutil.make_repo({
  { msg = "base", files = { ["f.txt"] = "one\ntwo\nthree\n" } },
  { msg = "c1: edit two", files = { ["f.txt"] = "one\nTWO\nthree\n" } },
  { msg = "c2: edit three + add g", files = {
    ["f.txt"] = "one\nTWO\nTHREE\n",
    ["g.txt"] = "gee\n",
  } },
})
local base = repo.shas[1]
local target = repo.shas[3]

local function inject_run(args)
  local cmd = { "git" }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local res = vim.system(cmd, { cwd = repo.root, env = repo.env, text = true }):wait()
  return { code = res.code, stdout = res.stdout, stderr = res.stderr }
end

local state_dir = vim.fn.tempname()
local function open(o)
  o = o or {}
  return glean.open({
    base = base,
    target = target,
    repo_root = repo.root,
    run = inject_run,
    open_window = false,
    state_dir = o.state_dir or state_dir,
    scope = o.scope,
  })
end

-- Render: both files appear as headers (expanded chevron) and bodies present.
do
  local s = open()
  local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local joined = table.concat(lines, "\n")
  h.assert_true("render: f.txt header", joined:find("▾ f.txt", 1, true) ~= nil)
  h.assert_true("render: g.txt header", joined:find("▾ g.txt", 1, true) ~= nil)
  h.assert_true("render: g.txt add kind", joined:find("g.txt %[add%]") ~= nil)
  h.assert_true("render: shows TWO add", joined:find("\n+TWO", 1, true) ~= nil)
  h.assert_true("render: shows hunk header", joined:find("@@", 1, true) ~= nil)
end

-- row_map: every rendered row resolves, headers carry file, body carries line.
do
  local s = open()
  local n = api.nvim_buf_line_count(s.buf)
  local all_mapped = true
  for row = 0, n - 1 do
    if not s.row_map[row] then all_mapped = false end
  end
  h.assert_true("row_map: every row mapped", all_mapped)
  h.assert_true("row_map: row 0 is a file header", s.row_map[0].file == 1 and s.row_map[0].hunk == nil)
  -- find a body line (has .line) and confirm it points into a hunk.
  local found_line = false
  for row = 0, n - 1 do
    local t = s.row_map[row]
    if t.line then found_line = true end
  end
  h.assert_true("row_map: has body line rows", found_line)
end

-- Collapse: toggling the first file hides its body; the other file is intact.
do
  local s = open()
  -- locate g.txt header row before collapse.
  local function header_row(path)
    for row, t in pairs(s.row_map) do
      if t.file and not t.hunk then
        local line = api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1]
        if line and line:find(path, 1, true) then return row end
      end
    end
  end
  local before = api.nvim_buf_line_count(s.buf)
  s:toggle_collapse(0) -- collapse file 1 (f.txt)
  local after = api.nvim_buf_line_count(s.buf)
  h.assert_true("collapse: buffer shrank", after < before)
  local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local joined = table.concat(lines, "\n")
  h.assert_true("collapse: f.txt now closed chevron", joined:find("▸ f.txt", 1, true) ~= nil)
  h.assert_true("collapse: f.txt body hidden", joined:find("\n+TWO", 1, true) == nil)
  h.assert_true("collapse: g.txt still present", joined:find("▾ g.txt", 1, true) ~= nil)
  h.assert_true("collapse: g.txt body intact", header_row("g.txt") ~= nil)
  -- expand again restores the body.
  s:toggle_collapse(0)
  local restored = api.nvim_buf_line_count(s.buf)
  h.assert_eq("collapse: re-expand restores rows", restored, before)
end

-- Helpers for commit-scope tests.
local function find_row(s, pred)
  local n = api.nvim_buf_line_count(s.buf)
  for row = 0, n - 1 do
    local line = api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1]
    if pred(row, line, s.row_map[row]) then return row, line end
  end
end

-- Commit scope: each commit is a header; seen markers present; line rows carry
-- commit/file/hunk/line in row_map.
do
  local s = open({ scope = "commits" })
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("commits: c1 header", joined:find(repo.shas[2]:sub(1, 8), 1, true) ~= nil)
  h.assert_true("commits: c2 header", joined:find(repo.shas[3]:sub(1, 8), 1, true) ~= nil)
  h.assert_true("commits: c1 summary", joined:find("c1: edit two", 1, true) ~= nil)
  -- every row maps; a body line row carries a full commit/file/hunk/line target.
  local n = api.nvim_buf_line_count(s.buf)
  local all = true
  for row = 0, n - 1 do
    if not s.row_map[row] then all = false end
  end
  h.assert_true("commits: every row mapped", all)
  local lrow = find_row(s, function(_, _, t) return t and t.commit and t.line end)
  h.assert_true("commits: has a body line row", lrow ~= nil)
end

-- toggle_seen on a commit header marks all of its hunks seen, persists, and on
-- reopen the commit shows ✓ and starts collapsed (collapse re-init from seen).
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local crow = find_row(s, function(_, _, t)
    return t and t.commit == 1 and not t.file
  end)
  h.assert_true("toggle: found c1 header", crow ~= nil)
  s:toggle_seen(crow)
  -- the store now records c1's f.txt new range (the TWO line at new_lnum 2).
  h.assert_true("toggle: c1 seen covers lnum 2",
    require("glean.state").covers(s.store:seen_ranges(repo.shas[2], "f.txt"), 2))

  -- reopen: persisted seen restored, commit collapsed via init_collapse.
  local s2 = open({ scope = "commits", state_dir = dir })
  local crow2, cline2 = find_row(s2, function(_, _, t)
    return t and t.commit == 1 and not t.file
  end)
  h.assert_true("reopen: c1 header has check", cline2:find("✓", 1, true) ~= nil)
  h.assert_true("reopen: c1 header collapsed chevron", cline2:find("▸", 1, true) ~= nil)
  -- collapsed means c1 body rows are gone; c1 file header should not render.
  local c1file = find_row(s2, function(_, _, t) return t and t.commit == 1 and t.file end)
  h.assert_true("reopen: c1 body hidden when collapsed", c1file == nil)
end

-- Comments: multiple comments on distinct lines and several on one line all
-- round-trip on the right (commit, path, new_lnum); restored on reopen.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  -- comment on c1's +TWO line (new_lnum 2 in f.txt).
  local trow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  h.assert_true("comment: found +TWO row", trow ~= nil)
  s:add_comment_at(trow, "first note")
  s:add_comment_at(trow, "second note")

  local reopened = open({ scope = "commits", state_dir = dir })
  local got = reopened.store:comments_at(repo.shas[2], "f.txt", 2)
  h.assert_eq("comment: count stacked", #got, 2)
  h.assert_eq("comment: first text", got[1].text, "first note")
  h.assert_eq("comment: second text", got[2].text, "second note")
  -- rendered as virt_lines below the line.
  local trow2 = find_row(reopened, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  local marks = api.nvim_buf_get_extmarks(reopened.buf,
    api.nvim_create_namespace("glean_comments"), { trow2, 0 }, { trow2, -1 },
    { details = true })
  h.assert_true("comment: virt_lines extmark present",
    #marks > 0 and marks[1][4].virt_lines ~= nil)
end

h.finish()
