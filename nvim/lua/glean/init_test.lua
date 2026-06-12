-- Tier 3a tests for glean.init: render the combined scope against a hermetic
-- git fixture and assert observable buffer state, row_map, and collapse
-- re-render. Run with:
--   nvim -l nvim/lua/glean/init_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local glean = require("glean.init")
local state = require("glean.state")
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
  h.assert_true("row_map: row 0 is a file header", s.row_map[0].cfile == 1 and s.row_map[0].hunk == nil)
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
      if (t.file or t.cfile) and not t.hunk then
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

-- Stage 4 — combined overlay via provenance.
-- (c)/(d): marking f.txt seen in combined routes each new line to its owning
-- commit (TWO -> c1, THREE -> c2); the file then drops to a "seen up to" row.
do
  local dir = vim.fn.tempname()
  local s = open({ state_dir = dir }) -- combined scope (default)
  local frow = find_row(s, function(_, line, t)
    return t and t.cfile and not t.hunk and line:find("f.txt", 1, true)
  end)
  h.assert_true("combined: found f.txt header", frow ~= nil)
  s:toggle_seen(frow)
  h.assert_true("combined: TWO seen on c1",
    state.covers(s.store:seen_ranges(repo.shas[2], "f.txt"), 2))
  h.assert_true("combined: THREE seen on c2",
    state.covers(s.store:seen_ranges(repo.shas[3], "f.txt"), 3))
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("combined: f.txt fully-seen row", joined:find("✓ f.txt", 1, true) ~= nil)
  h.assert_true("combined: f.txt body elided", joined:find("\n+TWO", 1, true) == nil)
  -- reopen: persisted seen still collapses f.txt in combined.
  local s2 = open({ state_dir = dir })
  local joined2 = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("combined reopen: f.txt still fully seen", joined2:find("✓ f.txt", 1, true) ~= nil)
  h.assert_true("combined reopen: g.txt still shown", joined2:find("▾ g.txt", 1, true) ~= nil)
end

-- (e): comments in combined route to the owning commit of each line.
do
  local dir = vim.fn.tempname()
  local s = open({ state_dir = dir })
  local r3 = find_row(s, function(_, line, t) return t and t.cfile and t.line and line == "+THREE" end)
  local r2 = find_row(s, function(_, line, t) return t and t.cfile and t.line and line == "+TWO" end)
  s:add_comment_at(r3, "on three")
  s:add_comment_at(r2, "on two")
  h.assert_eq("combined comment: THREE -> c2", #s.store:comments_at(repo.shas[3], "f.txt", 3), 1)
  h.assert_eq("combined comment: TWO -> c1", #s.store:comments_at(repo.shas[2], "f.txt", 2), 1)
end

-- (a)/(b)/(f): supersession + follow-up. c1 edits line2; c2 supersedes it.
do
  local r2 = testutil.make_repo({
    { msg = "base", files = { ["x.txt"] = "a\nb\nc\n" } },
    { msg = "c1: b->B1", files = { ["x.txt"] = "a\nB1\nc\n" } },
    { msg = "c2: b->B2", files = { ["x.txt"] = "a\nB2\nc\n" } },
  })
  local function run2(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = r2.root, env = r2.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local dir = vim.fn.tempname()
  local function open2(tgt)
    return glean.open({
      base = r2.shas[1], target = tgt, repo_root = r2.root, run = run2,
      open_window = false, state_dir = dir,
    })
  end
  -- combined net of base..c2: only line2 = B2 survives, owned by c2.
  local s = open2(r2.shas[3])
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("supersede: shows B2", joined:find("\n+B2", 1, true) ~= nil)
  h.assert_true("supersede: B1 never in combined", joined:find("B1", 1, true) == nil)
  -- Reviewing c1 alone (the superseded commit) does NOT mark the surviving
  -- line seen, because that line is owned by c2.
  local cs = open2(r2.shas[3])
  cs:set_scope("commits")
  local c1hdr = find_row(cs, function(_, _, t) return t and t.commit == 1 and not t.file end)
  cs:toggle_seen(c1hdr)
  local back = open2(r2.shas[3])
  local j2 = table.concat(api.nvim_buf_get_lines(back.buf, 0, -1, false), "\n")
  h.assert_true("supersede: B2 still unseen after reviewing c1", j2:find("\n+B2", 1, true) ~= nil)
  -- Follow-up: reviewing c2 fully seens the file; it collapses to a marker.
  local cs2 = open2(r2.shas[3])
  cs2:set_scope("commits")
  local c2hdr = find_row(cs2, function(_, _, t) return t and t.commit == 2 and not t.file end)
  cs2:toggle_seen(c2hdr)
  local done = open2(r2.shas[3])
  local j3 = table.concat(api.nvim_buf_get_lines(done.buf, 0, -1, false), "\n")
  h.assert_true("follow-up: x.txt fully seen after c2", j3:find("✓ x.txt", 1, true) ~= nil)
end

-- Re-diff branch: a file with two far-apart hunks from two commits; once the
-- earlier hunk is marked seen, the combined view re-diffs the tighter
-- Xe^..target range and shows a "seen up to" marker plus only the later hunk.
do
  local base_content = "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\n"
  local r3 = testutil.make_repo({
    { msg = "base", files = { ["y.txt"] = base_content } },
    { msg = "c1: edit l2", files = { ["y.txt"] = "l1\nL2\nl3\nl4\nl5\nl6\nl7\nl8\n" } },
    { msg = "c2: edit l7", files = { ["y.txt"] = "l1\nL2\nl3\nl4\nl5\nl6\nL7\nl8\n" } },
  })
  local function run3(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = r3.root, env = r3.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local dir = vim.fn.tempname()
  local function open3()
    return glean.open({
      base = r3.shas[1], target = r3.shas[3], repo_root = r3.root, run = run3,
      open_window = false, state_dir = dir,
    })
  end
  -- Mark only c1's L2 line seen on its owning commit.
  local s = open3()
  s.store:mark_seen(r3.shas[2], "y.txt", { 2, 2 })
  s.store:save_commit(r3.shas[2])
  local s2 = open3()
  local joined = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("redirff: seen-up-to marker shown", joined:find("seen up to", 1, true) ~= nil)
  h.assert_true("rediff: L7 (unseen) shown", joined:find("\n+L7", 1, true) ~= nil)
  h.assert_true("rediff: L2 hunk elided", joined:find("\n+L2", 1, true) == nil)
end

-- Stage 5 — jump-to-source.
-- Combined add line resolves to target (= repo HEAD here) so it opens the live
-- working-tree file; the returned path is the absolute working-tree path.
do
  local s = open()
  local r = find_row(s, function(_, line, t) return t and t.cfile and t.line and line == "+TWO" end)
  h.assert_true("jump: found +TWO row", r ~= nil)
  local jt = s:jump_target(r)
  h.assert_eq("jump: target ref is target", jt.ref, target)
  h.assert_eq("jump: target path", jt.path, "f.txt")
  h.assert_eq("jump: target lnum is new_lnum 2", jt.lnum, 2)
  h.assert_true("jump: target == HEAD", s:ref_is_head(target))
  local opened = s:jump(r)
  h.assert_eq("jump: opens live file path", opened, repo.root .. "/f.txt")
end

-- A deletion row resolves to the base (pre-image) ref, which is not HEAD, so it
-- opens a read-only `git show` scratch buffer with the old content and filetype.
do
  local s = open()
  local r = find_row(s, function(_, line, t)
    return t and t.cfile and t.line and line:sub(1, 1) == "-"
  end)
  h.assert_true("jump: found a deletion row", r ~= nil)
  local jt = s:jump_target(r)
  h.assert_eq("jump: del ref is base", jt.ref, base)
  h.assert_true("jump: base != HEAD", not s:ref_is_head(base))
  local buf = s:jump(r)
  h.assert_true("jump: scratch buffer created", type(buf) == "number")
  h.assert_eq("jump: scratch not modifiable",
    api.nvim_get_option_value("modifiable", { buf = buf }), false)
  local content = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  h.assert_true("jump: scratch has base content", content:find("two", 1, true) ~= nil)
end

-- Commit scope: an add line in a non-HEAD commit (c1) opens a `git show`
-- scratch buffer at that commit's post-image.
do
  local s = open({ scope = "commits" })
  local r = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  h.assert_true("jump commits: found c1 +TWO row", r ~= nil)
  local jt = s:jump_target(r)
  h.assert_eq("jump commits: ref is c1 sha", jt.ref, repo.shas[2])
  h.assert_eq("jump commits: lnum 2", jt.lnum, 2)
  h.assert_true("jump commits: c1 != HEAD", not s:ref_is_head(repo.shas[2]))
  local buf = s:jump(r)
  local content = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  h.assert_true("jump commits: shows TWO at post-image", content:find("TWO", 1, true) ~= nil)
end

h.finish()
