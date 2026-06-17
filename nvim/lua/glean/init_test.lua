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
  h.assert_true("render: f.txt header", joined:find("v f.txt", 1, true) ~= nil)
  h.assert_true("render: g.txt header", joined:find("v g.txt", 1, true) ~= nil)
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
  h.assert_true("row_map: row 0 is the mode header", s.row_map[0].cfile == nil and s.row_map[0].hunk == nil)
  h.assert_true("row_map: row 1 is a file header", s.row_map[1].cfile == 1 and s.row_map[1].hunk == nil)
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
  s:toggle_collapse(header_row("f.txt")) -- collapse file 1 (f.txt)
  local after = api.nvim_buf_line_count(s.buf)
  h.assert_true("collapse: buffer shrank", after < before)
  local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local joined = table.concat(lines, "\n")
  h.assert_true("collapse: f.txt now closed chevron", joined:find("> f.txt", 1, true) ~= nil)
  h.assert_true("collapse: f.txt body hidden", joined:find("\n+TWO", 1, true) == nil)
  h.assert_true("collapse: g.txt still present", joined:find("v g.txt", 1, true) ~= nil)
  h.assert_true("collapse: g.txt body intact", header_row("g.txt") ~= nil)
  -- expand again restores the body.
  s:toggle_collapse(header_row("f.txt"))
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
-- reopen the commit shows ✓ (commits never collapse; their files stay visible).
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
  -- commits never collapse: the file paths within the commit stay visible.
  local c1file = find_row(s2, function(_, _, t) return t and t.commit == 1 and t.file end)
  h.assert_true("reopen: c1 body still visible", c1file ~= nil)
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
  local got = reopened.store:comments_for("f.txt")
  h.assert_eq("comment: count stacked", #got, 2)
  h.assert_eq("comment: first text", got[1].text, "first note")
  h.assert_eq("comment: second text", got[2].text, "second note")
  -- rendered as real, cursor-addressable lines below the diff line.
  local crow = find_row(reopened, function(_, line, t)
    return t and t.comment and line:find("first note", 1, true) ~= nil
  end)
  h.assert_true("comment: inline row present", crow ~= nil)
  local ct = reopened.row_map[crow].comment
  h.assert_eq("comment: row carries identity", ct.text, "first note")
end

-- Delete comment: removing a comment drops it from the store and is undoable.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local trow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  s:add_comment_at(trow, "to delete")
  h.assert_eq("delete: present before", #s.store:comments_for("f.txt"), 1)
  s:delete_comment_at(trow)
  h.assert_eq("delete: gone after", #s.store:comments_for("f.txt"), 0)
  s:undo()
  h.assert_eq("delete: undo restores", #s.store:comments_for("f.txt"), 1)
  -- persisted across reopen.
  local s2 = open({ scope = "commits", state_dir = dir })
  h.assert_eq("delete: restore persisted", #s2.store:comments_for("f.txt"), 1)
end

-- Authoring a single-line comment through the ephemeral editor split: writing
-- the scratch buffer submits its text to the anchored line.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local trow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  s:open_comment_editor({}, function(text) s:add_comment_at(trow, text) end)
  local ebuf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(ebuf, 0, -1, false, { "a single note" })
  vim.cmd("write")
  local got = s.store:comments_for("f.txt")
  h.assert_eq("author: stored one comment", #got, 1)
  h.assert_eq("author: text round-trips", got[1].text, "a single note")
  local crow = find_row(s, function(_, line, t)
    return t and t.comment and line:find("a single note", 1, true) ~= nil
  end)
  h.assert_true("author: inline row present", crow ~= nil)
end

-- Authoring a multi-line comment: stored with embedded newlines and rendered
-- across multiple cursor-addressable rows that share one comment identity.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local trow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  s:open_comment_editor({}, function(text) s:add_comment_at(trow, text) end)
  local ebuf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(ebuf, 0, -1, false, { "first line", "second line" })
  vim.cmd("write")
  local got = s.store:comments_for("f.txt")
  h.assert_eq("multiline: stored one comment", #got, 1)
  h.assert_eq("multiline: newline preserved", got[1].text, "first line\nsecond line")
  local r1 = find_row(s, function(_, line, t)
    return t and t.comment and line:find("💬 first line", 1, true) ~= nil
  end)
  local r2 = find_row(s, function(_, line, t)
    return t and t.comment and line:find("second line", 1, true) ~= nil
      and line:find("💬", 1, true) == nil
  end)
  h.assert_true("multiline: first row present", r1 ~= nil)
  h.assert_true("multiline: continuation row present", r2 ~= nil)
  h.assert_eq("multiline: rows share identity",
    s.row_map[r1].comment.text, s.row_map[r2].comment.text)
end

-- Visual multi-line comment: a selection spanning several diff rows plus a
-- decoration row (the hunk header) stores one comment whose content is the
-- trimmed contiguous diff-line run, rendered inline exactly once.
do
  local dir = vim.fn.tempname()
  local s = open({ state_dir = dir }) -- combined
  local hrow = find_row(s, function(_, line, t)
    return t and t.cfile and t.hunk and not t.line and line:find("@@", 1, true)
  end)
  local twrow = find_row(s, function(_, line, t)
    return t and t.cfile and t.line and line == "+TWO"
  end)
  h.assert_true("visual: hunk header row", hrow ~= nil)
  h.assert_true("visual: +TWO row", twrow ~= nil)
  local ct = s:visual_comment_target(hrow, twrow)
  h.assert_true("visual: target captured", ct ~= nil)
  h.assert_true("visual: multi-line content", #ct.content >= 2)
  for _, c in ipairs(ct.content) do
    h.assert_true("visual: content excludes decoration", c:find("@@", 1, true) == nil)
  end
  s:add_comment(ct, "block note")
  h.assert_eq("visual: one comment stored", #s.store:comments_for("f.txt"), 1)
  local inline = 0
  for _, t in pairs(s.row_map) do
    if t and t.comment and t.comment.text == "block note" then inline = inline + 1 end
  end
  h.assert_eq("visual: rendered inline once", inline, 1)
end

-- Re-anchoring: a comment resolves by content even when its stored anchor is
-- stale (renders inline, not outdated); when its content is gone it renders
-- outdated and is listed in the summary.
do
  local dir = vim.fn.tempname()
  local s = open({ state_dir = dir }) -- combined
  s.store:add_comment_record("f.txt", { anchor = 1, content = { "TWO" }, text = "moved note" })
  s.store:save_commit(state.COMMENTS_ID)
  s:render()
  local inline = find_row(s, function(_, line, t)
    return t and t.comment and t.comment.text == "moved note"
  end)
  h.assert_true("reanchor: resolves by content", inline ~= nil)
  h.assert_true("reanchor: not outdated", s.row_map[inline].comment.outdated == false)
  s.store:add_comment_record("f.txt", { anchor = 2, content = { "VANISHED" }, text = "gone note" })
  s.store:save_commit(state.COMMENTS_ID)
  s:render()
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("reanchor: outdated in summary", joined:find("(Outdated)", 1, true) ~= nil)
  h.assert_true("reanchor: outdated text present", joined:find("💬 gone note", 1, true) ~= nil)
end

-- Deleting a comment from its inline row (the `dd` path) drops it from the
-- store and is undoable.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local trow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  s:add_comment_at(trow, "kill me")
  local crow = find_row(s, function(_, line, t)
    return t and t.comment and line:find("kill me", 1, true) ~= nil
  end)
  h.assert_true("dd: inline row before", crow ~= nil)
  s:delete_comment_under(crow)
  h.assert_eq("dd: removed from store", #s.store:comments_for("f.txt"), 0)
  s:undo()
  h.assert_eq("dd: undo restores", #s.store:comments_for("f.txt"), 1)
end

-- Comment summary: a per-file section at the bottom lists each comment with its
-- line number and affected line; comments on superseded lines are flagged
-- Outdated with the originating commit's short sha.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  -- present comment: c1's +TWO line (content "TWO" still in the diff at line 2).
  local twrow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  s:add_comment_at(twrow, "live note")
  -- outdated comment: a record whose content no longer appears in any diff line.
  s.store:add_comment_record("f.txt", { anchor = 99, content = { "ZZZ gone" }, text = "stale note" })
  s.store:save_commit(state.COMMENTS_ID)
  s:render()

  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("summary: section header present",
    joined:find("══ comments ══", 1, true) ~= nil)
  h.assert_true("summary: file path listed", joined:find("\nf.txt", 1, true) ~= nil)
  h.assert_true("summary: live comment text", joined:find("💬 live note", 1, true) ~= nil)
  h.assert_true("summary: stale comment text", joined:find("💬 stale note", 1, true) ~= nil)
  h.assert_true("summary: present comment not outdated",
    joined:find("L2  TWO", 1, true) ~= nil)
  h.assert_true("summary: outdated comment flagged",
    joined:find("(Outdated)", 1, true) ~= nil)
end

-- Comment summary (out-of-range owner): a comment authored in combined scope on
-- an unchanged context line is owned by a commit outside base..target, so it
-- never appears in any in-range commit's diff. It must still surface in the
-- bottom summary.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "combined", state_dir = dir })
  -- context " one" is owned by the base commit (not in base..target).
  local crow = find_row(s, function(_, line, t)
    return t and t.cfile and t.line and line == " one"
  end)
  h.assert_true("ctx-summary: found context one row", crow ~= nil)
  s:add_comment_at(crow, "context note")
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("ctx-summary: section header present",
    joined:find("══ comments ══", 1, true) ~= nil)
  h.assert_true("ctx-summary: context comment listed",
    joined:find("💬 context note", 1, true) ~= nil)
  -- survives reopen (owner shard loaded on demand).
  local s2 = open({ scope = "combined", state_dir = dir })
  local joined2 = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("ctx-summary: persists across reopen",
    joined2:find("💬 context note", 1, true) ~= nil)
end
-- Stage 2 — commits-scope seen section: marking an expanded file's only hunk
-- seen tucks it under a default-collapsed " seen (N hunks)" header.
do
  local s = open({ scope = "commits", state_dir = vim.fn.tempname() })
  local frow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.file and not t.hunk and line:find("f.txt", 1, true)
  end)
  h.assert_true("seen-section: found c1 f.txt header", frow ~= nil)
  s:toggle_seen(frow)
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("seen-section: header present",
    joined:find(" seen (1 hunks)", 1, true) ~= nil)
  h.assert_true("seen-section: collapsed chevron",
    joined:find("> seen", 1, true) ~= nil)
  h.assert_true("seen-section: seen hunk body hidden", joined:find("\n+TWO", 1, true) == nil)
  -- the seen-section row carries a {seen=true} target with no hunk/line.
  local srow = find_row(s, function(_, _, t)
    return t and t.commit == 1 and t.seen and not t.hunk
  end)
  h.assert_true("seen-section: row has seen target", srow ~= nil)
end

-- Stage 2 — marker rendering: a partial seen run inside an unseen hunk renders
-- as a default-collapsed "✓ marked N lines" row; the marked lines are hidden
-- while the rest of the hunk stays visible and the hunk remains unseen.
do
  local mrepo = testutil.make_repo({
    { msg = "base", files = { ["m.txt"] = "head\n" } },
    { msg = "c1: add block", files = { ["m.txt"] = "head\nL1\nL2\nL3\nL4\n" } },
  })
  local mdir = vim.fn.tempname()
  local mrun = function(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = mrepo.root, env = mrepo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = mrepo.shas[1], target = mrepo.shas[2], repo_root = mrepo.root,
    run = mrun, open_window = false, state_dir = mdir, scope = "commits",
  })
  -- mark new-file lines 2..3 (L1,L2) seen, leaving L3,L4 unseen.
  local csha = mrepo.shas[2]
  s.store:mark_seen(csha, "m.txt", { 2, 3 })
  s.store:save_commit(csha)
  s:render()
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("marker: collapsed row present", joined:find("✓ marked 2 lines", 1, true) ~= nil)
  h.assert_true("marker: marked lines hidden", joined:find("\n+L1", 1, true) == nil)
  h.assert_true("marker: marked lines hidden 2", joined:find("\n+L2", 1, true) == nil)
  h.assert_true("marker: unseen lines visible", joined:find("\n+L3", 1, true) ~= nil)
  h.assert_true("marker: hunk stays unseen", joined:find(" seen (", 1, true) == nil)
  -- the marker row carries a {marker=...} target with no line and the right span.
  local mrow = find_row(s, function(_, _, t) return t and t.marker and not t.line end)
  h.assert_true("marker: row has marker target", mrow ~= nil)
  local mk = s.row_map[mrow].marker
  h.assert_eq("marker: span lo lnum", mk.lnum_lo, 2)
  h.assert_eq("marker: span hi lnum", mk.lnum_hi, 3)
  h.assert_eq("marker: run length", mk.n, 2)
  -- expanding the marker (flip its collapse key) shows the marked lines with the
  -- seen highlight, under an open-chevron header.
  local key = glean._internal.marker_key("m.txt", mk.texts)
  s.collapse[key] = false
  s:render()
  local joined2 = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("marker: expanded header", joined2:find("v ✓ marked 2 lines", 1, true) ~= nil)
  h.assert_true("marker: expanded shows L1", joined2:find("\n+L1", 1, true) ~= nil)
  h.assert_true("marker: expanded shows L2", joined2:find("\n+L2", 1, true) ~= nil)
end

-- Deletion lines collapse into a marker too: visually marking only the deleted
-- rows of a mixed (del+add) hunk yields a "✓ marked N lines" marker, hides those
-- rows, records a committed del identity, and leaves the hunk unseen (its add
-- line is still unreviewed). Regression: del lines (no new_lnum) used to be
-- ignored by the marker scan, so a del-only mark never collapsed.
do
  local drepo = testutil.make_repo({
    { msg = "base", files = { ["d.txt"] = "head\nA\nB\nC\nfoot\n" } },
    { msg = "c1: rework", files = { ["d.txt"] = "head\nX\nfoot\n" } },
  })
  local ddir = vim.fn.tempname()
  local drun = function(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = drepo.root, env = drepo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = drepo.shas[1], target = drepo.shas[2], repo_root = drepo.root,
    run = drun, open_window = false, state_dir = ddir, scope = "commits",
  })
  local function drow(text)
    return find_row(s, function(_, line, t) return t and t.line and line == text end)
  end
  s:mark_visual_range(drow("-A"), drow("-C"))
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("del marker: collapsed row present", joined:find("✓ marked 3 lines", 1, true) ~= nil)
  h.assert_true("del marker: deleted rows hidden", joined:find("\n-A", 1, true) == nil)
  h.assert_true("del marker: add line still visible", joined:find("\n+X", 1, true) ~= nil)
  h.assert_true("del marker: hunk stays unseen", joined:find(" seen (", 1, true) == nil)
  h.assert_true("del marker: committed del identity stored",
    #s.store:seen_del_ranges(drepo.shas[2], "d.txt") > 0)
end

-- Stage 3 — marker interaction: visual `m` marks a sub-range (creating a
-- marker), `=` toggles it open/closed (persisting across reload), and normal
-- `m` on a marker row/line unmarks the whole run.
-- Stage 3 — marker interaction: visual `m` marks a sub-range (creating a
-- marker), `=` toggles it open/closed (persisting across reload), and normal
-- `m` on a marker row/line unmarks the whole run.
do
  local mrepo = testutil.make_repo({
    { msg = "base", files = { ["m.txt"] = "head\n" } },
    { msg = "c1: add block", files = { ["m.txt"] = "head\nL1\nL2\nL3\nL4\n" } },
  })
  local mdir = vim.fn.tempname()
  local mrun = function(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = mrepo.root, env = mrepo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local csha = mrepo.shas[2]
  local function fresh()
    return glean.open({
      base = mrepo.shas[1], target = csha, repo_root = mrepo.root,
      run = mrun, open_window = false, state_dir = mdir, scope = "commits",
    })
  end
  local function lrow(s, text)
    return find_row(s, function(_, line, t)
      return t and t.line and t.sec == "unseen" and line == text
    end)
  end

  -- Behavior 1 (mark): visual `m` over +L1,+L2 creates a marker.
  local s = fresh()
  local r1, r2 = lrow(s, "+L1"), lrow(s, "+L2")
  s:mark_visual_range(r1, r2)
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("stage3 mark: marker present", joined:find("✓ marked 2 lines", 1, true) ~= nil)
  h.assert_eq("stage3 mark: store has range", #s.store:seen_ranges(csha, "m.txt"), 1)

  -- Behavior 2 (supersede): mark +L3 too -> single merged marker of 3 lines.
  local r3 = lrow(s, "+L3")
  s:mark_visual_range(r3, r3)
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("stage3 supersede: merged marker", joined:find("✓ marked 3 lines", 1, true) ~= nil)
  h.assert_true("stage3 supersede: no 2-line marker", joined:find("marked 2 lines", 1, true) == nil)
  h.assert_eq("stage3 supersede: one merged range", #s.store:seen_ranges(csha, "m.txt"), 1)

  -- Behavior 4 (toggle): `=` on the marker row expands it; `=` again collapses;
  -- the expanded state survives reload.
  local mrow = find_row(s, function(_, _, t) return t and t.marker and not t.line end)
  s:toggle_collapse(mrow)
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("stage3 toggle: expanded after =", joined:find("v ✓ marked 3 lines", 1, true) ~= nil)
  h.assert_true("stage3 toggle: shows L1", joined:find("\n+L1", 1, true) ~= nil)
  s:reload()
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("stage3 toggle: expansion survives reload", joined:find("v ✓ marked 3 lines", 1, true) ~= nil)
  local mrow2 = find_row(s, function(_, _, t) return t and t.marker and not t.line end)
  s:toggle_collapse(mrow2)
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("stage3 toggle: collapsed after second =", joined:find("\n  ✓ marked 3 lines", 1, true) ~= nil)

  -- Behavior 3 (unmark): `m` on the collapsed marker row removes the run.
  local mrow3 = find_row(s, function(_, _, t) return t and t.marker and not t.line end)
  s:toggle_seen(mrow3)
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("stage3 unmark: marker gone", joined:find("marked", 1, true) == nil)
  h.assert_true("stage3 unmark: lines visible again", joined:find("\n+L1", 1, true) ~= nil)
  h.assert_eq("stage3 unmark: store empty", #s.store:seen_ranges(csha, "m.txt"), 0)

  -- Behavior 3b (unmark via expanded line): mark, expand, `m` on a marked line.
  local s2 = fresh()
  s2:mark_visual_range(lrow(s2, "+L1"), lrow(s2, "+L2"))
  local mr = find_row(s2, function(_, _, t) return t and t.marker and not t.line end)
  s2:toggle_collapse(mr)
  local mline = find_row(s2, function(_, line, t)
    return t and t.marker and t.line and line == "+L1"
  end)
  s2:toggle_seen(mline)
  joined = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("stage3 unmark-line: marker gone", joined:find("marked", 1, true) == nil)
  h.assert_eq("stage3 unmark-line: store empty", #s2.store:seen_ranges(csha, "m.txt"), 0)

  -- Behavior 5 (whole-hunk transition): marking all add lines fully seens the
  -- hunk; it moves to the seen section and draws no marker rows.
  local s3 = fresh()
  s3:mark_visual_range(lrow(s3, "+L1"), lrow(s3, "+L4"))
  joined = table.concat(api.nvim_buf_get_lines(s3.buf, 0, -1, false), "\n")
  h.assert_true("stage3 whole-hunk: seen section", joined:find(" seen (", 1, true) ~= nil)
  h.assert_true("stage3 whole-hunk: no marker", joined:find("marked", 1, true) == nil)

  -- Behavior 6 (fall-through): normal `m` on an ordinary hunk line still toggles
  -- the whole hunk seen. Uses its own store so the hunk starts unseen (the
  -- shared mdir already has it fully marked from the prior whole-hunk behavior).
  local s4 = glean.open({
    base = mrepo.shas[1], target = csha, repo_root = mrepo.root,
    run = mrun, open_window = false, state_dir = vim.fn.tempname(), scope = "commits",
  })
  local hline = lrow(s4, "+L1")
  s4:toggle_seen(hline)
  joined = table.concat(api.nvim_buf_get_lines(s4.buf, 0, -1, false), "\n")
  h.assert_true("stage3 fall-through: whole hunk seen", joined:find(" seen (", 1, true) ~= nil)
  h.assert_eq("stage3 fall-through: all lines seen",
    #s4.store:seen_ranges(csha, "m.txt"), 1)
end

-- Stage 3 — identity-only action layer: marking a hunk addresses only its
-- changed (add/del) lines, never the surrounding context (no "filling"); and
-- mark/unmark and undo/redo round-trip the seen set byte-identically.
do
  local irepo = testutil.make_repo({
    { msg = "base", files = { ["i.txt"] = "a\nb\nc\n" } },
    { msg = "c1: insert INS", files = { ["i.txt"] = "a\nb\nINS\nc\n" } },
  })
  local irun = function(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = irepo.root, env = irepo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local ish = irepo.shas[2]
  local function iopen(dir)
    return glean.open({
      base = irepo.shas[1], target = ish, repo_root = irepo.root,
      run = irun, open_window = false, state_dir = dir, scope = "commits",
    })
  end
  local function encode_shard(s)
    return vim.json.encode(s.store.data[ish] or { files = {} })
  end

  -- Marking the hunk covers only the add line (new_lnum 3), never the context
  -- lines (1, 2, 4): context carries no identity, so it is never filled.
  local s = iopen(vim.fn.tempname())
  local insrow = find_row(s, function(_, line, t)
    return t and t.commit and t.line and t.sec == "unseen" and line == "+INS"
  end)
  local empty = encode_shard(s)
  s:toggle_seen(insrow)
  local seen = s.store:seen_ranges(ish, "i.txt")
  h.assert_true("stage3 ctx: add line 3 seen", state.covers(seen, 3))
  h.assert_true("stage3 ctx: context 2 not filled", not state.covers(seen, 2))
  h.assert_true("stage3 ctx: context 4 not filled", not state.covers(seen, 4))

  -- Mark then unmark the same hunk restores the shard byte-identically.
  s:toggle_seen(find_row(s, function(_, _, t)
    return t and t.commit and t.file and not t.hunk and not t.line
  end))
  h.assert_eq("stage3 roundtrip: shard byte-identical after mark+unmark",
    encode_shard(s), empty)

  -- Undo/redo restore the exact seen-identity set.
  local s2 = iopen(vim.fn.tempname())
  local before = encode_shard(s2)
  s2:toggle_seen(find_row(s2, function(_, line, t)
    return t and t.commit and t.line and t.sec == "unseen" and line == "+INS"
  end))
  local marked = encode_shard(s2)
  h.assert_true("stage3 undo: mark changed the shard", marked ~= before)
  s2:undo()
  h.assert_eq("stage3 undo: restores prior set", encode_shard(s2), before)
  s2:redo()
  h.assert_eq("stage3 redo: re-applies the mark", encode_shard(s2), marked)
end

-- Unseen section: changed hunks render under a default-expanded
-- "unseen (N hunks)" header. Collapsing any row in the section (here a diff
-- line) hides the section body but leaves the file header in place.
do
  local s = open({ state_dir = vim.fn.tempname() })
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("unseen-section: header present", joined:find("unseen (", 1, true) ~= nil)
  h.assert_true("unseen-section: default expanded chevron", joined:find("v unseen", 1, true) ~= nil)
  h.assert_true("unseen-section: body shown", joined:find("\n+TWO", 1, true) ~= nil)

  local lrow = find_row(s, function(_, _, t) return t and t.line and t.sec == "unseen" end)
  h.assert_true("unseen-section: found a line row", lrow ~= nil)
  s:toggle_collapse(lrow)
  local j2 = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("unseen-section: collapsed chevron", j2:find("> unseen", 1, true) ~= nil)
  h.assert_true("unseen-section: body hidden", j2:find("\n+TWO", 1, true) == nil)
  h.assert_true("unseen-section: file header intact", j2:find("v f.txt", 1, true) ~= nil)
  s:toggle_collapse(find_row(s, function(_, _, t) return t and t.unseen end))
  local j3 = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("unseen-section: re-expanded body", j3:find("\n+TWO", 1, true) ~= nil)
end

-- Undo / redo: marking seen pushes an undo snapshot; undo reverts the store and
-- redo re-applies it. Persists through reopen.
do
  local state = require("glean.state")
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local frow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.file and not t.hunk and line:find("f.txt", 1, true)
  end)
  s:toggle_seen(frow)
  h.assert_true("undo: marked seen", state.covers(s.store:seen_ranges(repo.shas[2], "f.txt"), 2))
  s:undo()
  h.assert_true("undo: reverted", not state.covers(s.store:seen_ranges(repo.shas[2], "f.txt"), 2))
  s:redo()
  h.assert_true("undo: redo re-applied", state.covers(s.store:seen_ranges(repo.shas[2], "f.txt"), 2))
  -- redo persisted to disk: reopen reflects the seen range.
  local s2 = open({ scope = "commits", state_dir = dir })
  h.assert_true("undo: redo persisted", state.covers(s2.store:seen_ranges(repo.shas[2], "f.txt"), 2))
end

-- Undo / redo for comment and collapse actions.
do
  local dir = vim.fn.tempname()
  local s = open({ scope = "commits", state_dir = dir })
  local crow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.line and line == "+TWO"
  end)
  s:add_comment_at(crow, "hi")
  h.assert_eq("comment-undo: added", #s.store:comments_for("f.txt"), 1)
  s:undo()
  h.assert_eq("comment-undo: removed", #s.store:comments_for("f.txt"), 0)
  s:redo()
  h.assert_eq("comment-undo: re-added", #s.store:comments_for("f.txt"), 1)

  -- collapse: toggling a file header then undo restores expanded state.
  local function frow()
    return find_row(s, function(_, line, t)
      return t and t.commit == 1 and t.file and not t.hunk and line:find("f.txt", 1, true)
    end)
  end
  local function fline()
    return select(2, find_row(s, function(_, line, t)
      return t and t.commit == 1 and t.file and not t.hunk and line:find("f.txt", 1, true)
    end))
  end
  s:toggle_collapse(frow())
  h.assert_true("collapse-undo: collapsed", fline():find(">", 1, true) ~= nil)
  s:undo()
  h.assert_true("collapse-undo: re-expanded", fline():find("v", 1, true) ~= nil)
  s:redo()
  h.assert_true("collapse-undo: re-collapsed", fline():find(">", 1, true) ~= nil)
  -- restore expanded: collapse overrides are keyed by base/target and shared
  -- across sessions, so leave f.txt expanded for later bare-open tests.
  s:undo()
  h.assert_true("collapse-undo: left expanded", fline():find("v", 1, true) ~= nil)
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
  h.assert_true("combined: f.txt seen section", joined:find(" seen (1 hunks)", 1, true) ~= nil)
  h.assert_true("combined: f.txt header still shown", joined:find("v f.txt", 1, true) ~= nil)
  h.assert_true("combined: f.txt body elided", joined:find("\n+TWO", 1, true) == nil)
  -- reopen: persisted seen still collapses f.txt in combined.
  local s2 = open({ state_dir = dir })
  local joined2 = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("combined reopen: f.txt still fully seen", joined2:find(" seen", 1, true) ~= nil)
  h.assert_true("combined reopen: g.txt still shown", joined2:find("v g.txt", 1, true) ~= nil)
end

-- Stage 4 — combined-scope markers: a partial seen run inside an unseen hunk
-- whose lines are owned by two different commits. Marking the sub-range routes
-- each line to its owner store; the run renders as one marker; `=` toggles it;
-- `m` unmarks both owners.
do
  local crepo = testutil.make_repo({
    { msg = "base", files = { ["mm.txt"] = "ctx\n" } },
    { msg = "c1: add A1", files = { ["mm.txt"] = "ctx\nA1\n" } },
    { msg = "c2: add A2,A3", files = { ["mm.txt"] = "ctx\nA1\nA2\nA3\n" } },
  })
  local crun = function(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = crepo.root, env = crepo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local cdir = vim.fn.tempname()
  local function copen()
    return glean.open({
      base = crepo.shas[1], target = crepo.shas[3], repo_root = crepo.root,
      run = crun, open_window = false, state_dir = cdir, scope = "combined",
    })
  end
  local function crow(s, text)
    return find_row(s, function(_, line, t)
      return t and t.cfile and t.line and t.sec == "unseen" and line == text
    end)
  end

  -- Mark A1 (owned c1) + A2 (owned c2); A3 stays unseen so the hunk stays
  -- unseen and the run collapses to a single marker.
  local s = copen()
  s:mark_visual_range(crow(s, "+A1"), crow(s, "+A2"))
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("combined marker: marker present", joined:find("✓ marked 2 lines", 1, true) ~= nil)
  h.assert_true("combined marker: hunk stays unseen", joined:find(" seen (", 1, true) == nil)
  h.assert_true("combined marker: A3 still visible", joined:find("\n+A3", 1, true) ~= nil)
  h.assert_true("combined marker: A1 hidden", joined:find("\n+A1", 1, true) == nil)
  -- Each line routed to its owning commit's store.
  h.assert_true("combined marker: A1 seen on c1",
    state.covers(s.store:seen_ranges(crepo.shas[2], "mm.txt"), 2))
  h.assert_true("combined marker: A2 seen on c2",
    state.covers(s.store:seen_ranges(crepo.shas[3], "mm.txt"), 3))

  -- `=` toggles the marker open (cmarker_key) then closed.
  local mrow = find_row(s, function(_, _, t) return t and t.marker and not t.line end)
  s:toggle_collapse(mrow)
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("combined marker: expanded after =", joined:find("v ✓ marked 2 lines", 1, true) ~= nil)
  h.assert_true("combined marker: expanded shows A1", joined:find("\n+A1", 1, true) ~= nil)

  -- `m` on the marker unmarks both owners' stores.
  local mrow2 = find_row(s, function(_, _, t) return t and t.marker and not t.line end)
  s:toggle_seen(mrow2)
  joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("combined marker: marker gone after unmark", joined:find("marked", 1, true) == nil)
  h.assert_true("combined marker: A1 visible again", joined:find("\n+A1", 1, true) ~= nil)
  h.assert_eq("combined marker: c1 store empty", #s.store:seen_ranges(crepo.shas[2], "mm.txt"), 0)
  h.assert_eq("combined marker: c2 store empty", #s.store:seen_ranges(crepo.shas[3], "mm.txt"), 0)
end

-- (e): comments in combined route to the owning commit of each line.
do
  local dir = vim.fn.tempname()
  local s = open({ state_dir = dir })
  local r3 = find_row(s, function(_, line, t) return t and t.cfile and t.line and line == "+THREE" end)
  local r2 = find_row(s, function(_, line, t) return t and t.cfile and t.line and line == "+TWO" end)
  s:add_comment_at(r3, "on three")
  s:add_comment_at(r2, "on two")
  h.assert_eq("combined comment: both stored on f.txt", #s.store:comments_for("f.txt"), 2)
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
  h.assert_true("follow-up: x.txt fully seen after c2", j3:find(" seen", 1, true) ~= nil)
end

-- Re-diff branch: a file with two far-apart hunks from two commits; once the
-- earlier hunk is marked seen, the combined view re-diffs the tighter
-- Xe^..target range and shows a "seen up to" marker plus only the later hunk.
do
  local base_content = "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\n"
  local r3 = testutil.make_repo({
    { msg = "base", files = { ["y.txt"] = base_content } },
    { msg = "c1: edit l2", files = { ["y.txt"] = "l1\nL2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\n" } },
    { msg = "c2: edit l10", files = { ["y.txt"] = "l1\nL2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nL10\nl11\n" } },
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
  -- Mark the L2 hunk seen via the UI (routes each line, incl. context, to its
  -- owning commit). It forms its own hunk, separate from the L10 hunk.
  local s = open3()
  local l2row = find_row(s, function(_, line, t)
    return t and t.cfile and t.hunk and line:find("+L2", 1, true)
  end)
  s:toggle_seen(l2row)
  local s2 = open3()
  local joined = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("two-hunk: L2 seen section", joined:find(" seen (1 hunks)", 1, true) ~= nil)
  h.assert_true("two-hunk: L10 (unseen) shown", joined:find("\n+L10", 1, true) ~= nil)
  h.assert_true("two-hunk: L2 hunk collapsed", joined:find("\n+L2", 1, true) == nil)
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

-- Ephemeral split diff: a deletion row resolves to base (pre) / target (post),
-- and diffsplit lays out previous-on-left, target-on-right with diff mode on.
do
  local s = open()
  local r = find_row(s, function(_, line, t)
    return t and t.cfile and t.line and line:sub(1, 1) == "-"
  end)
  h.assert_true("diffsplit: found a deletion row", r ~= nil)
  local ctx = s:diff_context(r)
  h.assert_eq("diffsplit: post_ref is target", ctx.post_ref, target)
  h.assert_eq("diffsplit: pre_ref is base", ctx.pre_ref, base)
  h.assert_eq("diffsplit: path", ctx.path, "f.txt")
  local right_win, left_win = s:diffsplit(r)
  h.assert_true("diffsplit: returns two windows",
    type(right_win) == "number" and type(left_win) == "number")
  h.assert_true("diffsplit: left is left of right",
    api.nvim_win_get_position(left_win)[2] < api.nvim_win_get_position(right_win)[2])
  h.assert_true("diffsplit: both windows in diff mode",
    api.nvim_get_option_value("diff", { win = left_win })
      and api.nvim_get_option_value("diff", { win = right_win }))
  local lbuf = api.nvim_win_get_buf(left_win)
  local lcontent = table.concat(api.nvim_buf_get_lines(lbuf, 0, -1, false), "\n")
  h.assert_true("diffsplit: left has base content", lcontent:find("two", 1, true) ~= nil)
  api.nvim_win_close(left_win, true)
  if api.nvim_win_is_valid(right_win) then api.nvim_win_close(right_win, true) end
end

-- Stage 3 — the floating "worktree" commit in commit scope: content-hash seen
-- marks and content-anchored comments, persisted to a repo-scoped shard.
do
  local wt = testutil.make_repo({
    { msg = "base", files = { ["w.txt"] = "a\nb\nc\n" } },
  })
  local function write(path, content)
    local f = assert(io.open(wt.root .. "/" .. path, "w"))
    f:write(content)
    f:close()
  end
  write("w.txt", "a\nB\nc\n") -- unstaged edit
  write("u.txt", "alpha\nbeta\n") -- untracked
  local function runwt(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = wt.root, env = wt.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local function openwt(d)
    return glean.open({
      base = wt.shas[1], target = glean.WORKTREE, repo_root = wt.root, run = runwt,
      open_window = false, state_dir = d, scope = "commits",
    })
  end

  local seen_dir = vim.fn.tempname()
  -- Render: the floating commit appears last with its summary, and the untracked
  -- file shows up as an all-addition file alongside the tracked dirty edit.
  local s = openwt(seen_dir)
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_eq("worktree: floating commit id last", s.commits[#s.commits].sha, glean.WORKTREE)
  h.assert_true("worktree: floating summary", joined:find("uncommitted changes", 1, true) ~= nil)
  h.assert_true("worktree: untracked u.txt present", joined:find("u.txt", 1, true) ~= nil)
  h.assert_true("worktree: +B shown", joined:find("\n+B", 1, true) ~= nil)

  -- Mark the floating w.txt file seen: stores a content block and renders seen.
  local frow = find_row(s, function(_, line, t)
    return t and t.commit == #s.commits and t.file and not t.hunk and line:find("w.txt", 1, true)
  end)
  h.assert_true("worktree: found w.txt header", frow ~= nil)
  s:toggle_seen(frow)
  h.assert_true("worktree: content hash stored",
    next(s.store:seen_hashes(glean.WORKTREE, "w.txt")) ~= nil)
  -- reopen: working file unchanged, so the content hash still matches → fully seen.
  local s2 = openwt(seen_dir)
  local _, fline2 = find_row(s2, function(_, line, t)
    return t and t.commit == #s2.commits and t.file and not t.hunk and line:find("w.txt", 1, true)
  end)
  h.assert_true("worktree reopen: w.txt ✓", fline2:find("✓", 1, true) ~= nil)

  -- Comments anchor by line content (not number) and render on the matching line.
  local cdir = vim.fn.tempname()
  local sc = openwt(cdir)
  local crow = find_row(sc, function(_, line, t)
    return t and t.commit == #sc.commits and t.line and line == "+B"
  end)
  h.assert_true("worktree comment: found +B row", crow ~= nil)
  sc:add_comment_at(crow, "note on B")
  h.assert_eq("worktree comment: stored by content",
    #sc.store:comments_for("w.txt"), 1)
  local sc2 = openwt(cdir)
  local crow2 = find_row(sc2, function(_, line, t)
    return t and t.comment and line:find("note on B", 1, true) ~= nil
  end)
  h.assert_true("worktree comment: inline row present", crow2 ~= nil)

  -- Editing the underlying file content drops the content-hash seen flag (the
  -- stored block no longer matches any current window).
  write("w.txt", "a\nBB\nc\n")
  local s3 = openwt(seen_dir)
  local _, fline3 = find_row(s3, function(_, line, t)
    return t and t.commit == #s3.commits and t.file and not t.hunk and line:find("w.txt", 1, true)
  end)
  h.assert_true("worktree edit: w.txt seen dropped", fline3:find("✓", 1, true) == nil)
end

-- Stage 4 — combined overlay with the WORKTREE as target: a committed branch
-- edit plus an uncommitted edit in the same file. Blame attributes the dirty
-- line to the floating commit (zero sha -> WORKTREE); marking the combined file
-- routes the committed line to range-seen and the uncommitted line to hash-seen,
-- and a comment on the dirty line lands in the floating shard by content hash.
do
  local wm = testutil.make_repo({
    { msg = "base", files = { ["m.txt"] = "a\nb\nc\nd\n" } },
    { msg = "c1: b->B", files = { ["m.txt"] = "a\nB\nc\nd\n" } },
  })
  local function write(path, content)
    local f = assert(io.open(wm.root .. "/" .. path, "w"))
    f:write(content)
    f:close()
  end
  write("m.txt", "a\nB\nc\nD\n") -- uncommitted edit of line 4
  local function runwm(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = wm.root, env = wm.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local function openwm(d)
    return glean.open({
      base = wm.shas[1], target = glean.WORKTREE, repo_root = wm.root, run = runwm,
      open_window = false, state_dir = d, -- combined scope (default)
    })
  end

  local dir = vim.fn.tempname()
  local s = openwm(dir)
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  -- (a)/(b): committed and uncommitted edits both show; D is unseen initially.
  h.assert_true("wt combined: committed +B shown", joined:find("\n+B", 1, true) ~= nil)
  h.assert_true("wt combined: uncommitted +D shown", joined:find("\n+D", 1, true) ~= nil)
  h.assert_true("wt combined: m.txt not yet fully seen", joined:find(" seen", 1, true) == nil)
  -- The dirty line is owned by the floating commit (zero sha remapped).
  h.assert_eq("wt combined: +D owned by WORKTREE", s:provenance("m.txt")[4].sha, glean.WORKTREE)

  -- (c): mark the whole file seen — committed line -> range-seen on c1, dirty
  -- line -> content block on the floating shard.
  local frow = find_row(s, function(_, line, t)
    return t and t.cfile and not t.hunk and line:find("m.txt", 1, true)
  end)
  s:toggle_seen(frow)
  h.assert_true("wt combined: committed B range-seen on c1",
    state.covers(s.store:seen_ranges(wm.shas[2], "m.txt"), 2))
  h.assert_true("wt combined: dirty D hash-seen on WORKTREE",
    next(s.store:seen_hashes(glean.WORKTREE, "m.txt")) ~= nil)
  local jseen = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("wt combined: m.txt fully seen", jseen:find(" seen (1 hunks)", 1, true) ~= nil)
  -- reopen: persisted committed + floating seen still collapses the file.
  local s2 = openwm(dir)
  local j2 = table.concat(api.nvim_buf_get_lines(s2.buf, 0, -1, false), "\n")
  h.assert_true("wt combined reopen: m.txt still fully seen", j2:find(" seen", 1, true) ~= nil)

  -- (d): a comment on the dirty line lands in the floating shard by line hash.
  local cdir = vim.fn.tempname()
  local sc = openwm(cdir)
  local crow = find_row(sc, function(_, line, t) return t and t.cfile and t.line and line == "+D" end)
  h.assert_true("wt combined comment: found +D row", crow ~= nil)
  sc:add_comment_at(crow, "dirty note")
  h.assert_eq("wt combined comment: stored by content on WORKTREE",
    #sc.store:comments_for("m.txt"), 1)
end

-- Stage 5 — jump-to-source for the floating commit + the convenience command.
-- A floating add/context line opens the live working-tree file (LSP attaches);
-- a floating deletion opens the HEAD pre-image scratch. The dirty convenience
-- resolver yields merge_base(trunk, HEAD) -> WORKTREE.
do
  local jr = testutil.make_repo({
    { msg = "base", files = { ["j.txt"] = "a\nb\nc\n" } },
  })
  local function write(path, content)
    local f = assert(io.open(jr.root .. "/" .. path, "w"))
    f:write(content)
    f:close()
  end
  write("j.txt", "a\nB\nc\nz\n") -- unstaged edit (b->B) + appended line
  local function runj(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = jr.root, env = jr.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = jr.shas[1], target = glean.WORKTREE, repo_root = jr.root, run = runj,
    open_window = false, state_dir = vim.fn.tempname(), scope = "commits",
  })

  -- A floating add row resolves to the live work tree (ref == WORKTREE) and
  -- jump opens the absolute working-tree path.
  local addrow = find_row(s, function(_, line, t)
    return t and t.commit == #s.commits and t.line and line == "+B"
  end)
  h.assert_true("wt jump: found +B row", addrow ~= nil)
  local jt = s:jump_target(addrow)
  h.assert_eq("wt jump: add ref is WORKTREE", jt.ref, glean.WORKTREE)
  h.assert_eq("wt jump: add path", jt.path, "j.txt")
  local opened = s:jump(addrow)
  h.assert_eq("wt jump: opens live file", opened, jr.root .. "/j.txt")

  -- A floating deletion row resolves to the HEAD pre-image scratch.
  local delrow = find_row(s, function(_, line, t)
    return t and t.commit == #s.commits and t.line and line:sub(1, 1) == "-"
  end)
  if delrow then
    local djt = s:jump_target(delrow)
    h.assert_eq("wt jump: del ref is HEAD", djt.ref, "HEAD")
    local dbuf = s:jump(delrow)
    h.assert_true("wt jump: del scratch buffer", type(dbuf) == "number")
  end

  -- The convenience resolver. On the default branch with no upstream it falls
  -- back to the configured trunk name; the target is always the work tree.
  local git = require("glean.git").new({ repo_root = jr.root, run = runj })
  local base, tgt = glean.resolve_dirty(git)
  h.assert_eq("dirty resolver: target is WORKTREE", tgt, glean.WORKTREE)
  h.assert_eq("dirty resolver: base falls back to trunk on default branch",
    base, glean.config.default_base)

  -- On a feature branch the base is the fork point from the trunk (merge-base).
  runj({ "checkout", "-q", "-b", "feature" })
  write("j.txt", "a\nB\nc\nz\nq\n")
  runj({ "commit", "-q", "-am", "feature commit" })
  local fbase, ftgt = glean.resolve_dirty(git)
  h.assert_eq("dirty resolver (branch): target is WORKTREE", ftgt, glean.WORKTREE)
  h.assert_eq("dirty resolver (branch): base is trunk merge-base",
    fbase, git:merge_base("main", "HEAD"))
end

-- Content-addressed collapse overrides survive both a reopen and a live reload.
-- (file-level: commits themselves never collapse in commit scope.)
do
  local dir = vim.fn.tempname()
  local sha = repo.shas[2]
  local s = open({ scope = "commits", state_dir = dir })
  local frow = find_row(s, function(_, _, t)
    return t and t.commit and t.file and not t.line
  end)
  h.assert_true("collapse: found a file header", frow ~= nil)
  local ci, fi = s.row_map[frow].commit, s.row_map[frow].file
  local path = s.commits[ci].files[fi].path
  local before = s.commits[ci].files[fi].collapsed
  s:toggle_collapse(frow)
  local after = s.commits[ci].files[fi].collapsed
  h.assert_true("collapse: toggle flips state", before ~= after)
  local function collapsed_of(sess)
    for _, c in ipairs(sess.commits) do
      if c.sha == sha then
        for _, f in ipairs(c.files) do
          if f.path == path then return f.collapsed end
        end
      end
    end
  end
  local s2 = open({ scope = "commits", state_dir = dir })
  h.assert_eq("collapse: persists across reopen", collapsed_of(s2), after)
  s2:reload()
  h.assert_eq("collapse: persists across reload", collapsed_of(s2), after)
end

-- Persistent, listed buffer: reused across opens of the same diff, named Glean:.
do
  local dir = vim.fn.tempname()
  local s = open({ state_dir = dir })
  h.assert_true("buffer: listed", api.nvim_get_option_value("buflisted", { buf = s.buf }))
  local name = api.nvim_buf_get_name(s.buf)
  h.assert_true("buffer: Glean name", name:find("Glean:", 1, true) ~= nil)
  local s2 = open({ state_dir = dir })
  h.assert_eq("buffer: reused on reopen", s2.buf, s.buf)
end

-- Multi-hunk navigation: a file with three well-separated hunks (the third very
-- long) exercises move-to-next-hunk after a mark and scroll-into-view on ]c.
do
  local function lines_with(overrides, n)
    local t = {}
    for i = 1, n do t[i] = overrides[i] or ("line" .. i) end
    return table.concat(t, "\n") .. "\n"
  end
  local base_overrides = {}
  local tgt_overrides = { [10] = "line10_X", [30] = "line30_Y" }
  for i = 50, 89 do tgt_overrides[i] = "line" .. i .. "_Z" end
  local mrepo = testutil.make_repo({
    { msg = "base", files = { ["m.txt"] = lines_with(base_overrides, 90) } },
    { msg = "edit", files = { ["m.txt"] = lines_with(tgt_overrides, 90) } },
  })
  local function open_m()
    return glean.open({
      base = mrepo.shas[1],
      target = mrepo.shas[2],
      repo_root = mrepo.root,
      run = function(args)
        local cmd = { "git" }
        for _, a in ipairs(args) do cmd[#cmd + 1] = a end
        local res = vim.system(cmd, { cwd = mrepo.root, env = mrepo.env, text = true }):wait()
        return { code = res.code, stdout = res.stdout, stderr = res.stderr }
      end,
      open_window = true,
      state_dir = vim.fn.tempname(),
    })
  end

  local function hunk_headers(s)
    local hs = {}
    local n = api.nvim_buf_line_count(s.buf)
    for row = 0, n - 1 do
      local t = s.row_map[row]
      if t and t.hunk and not t.line and t.sec ~= "seen" then hs[#hs + 1] = row end
    end
    return hs
  end

  -- test 1: mark a middle line of hunk 1 seen; cursor lands on hunk 2's header.
  do
    local s = open_m()
    local hs = hunk_headers(s)
    h.assert_true("multihunk: three hunks rendered", #hs == 3)
    local h1 = s.row_map[hs[1]]
    local h2 = s.row_map[hs[2]]
    -- a body line of hunk 1 (between its header and hunk 2's header).
    local mid
    for row = hs[1] + 1, hs[2] - 1 do
      local t = s.row_map[row]
      if t and t.line and t.cfile == h1.cfile and t.hunk == h1.hunk then mid = row break end
    end
    h.assert_true("multihunk: found hunk 1 body line", mid ~= nil)
    s:toggle_seen(mid)
    local cur = s:cursor_row()
    local ct = s.row_map[cur]
    h.assert_true("multihunk: cursor on a hunk header after mark",
      ct and ct.hunk and not ct.line)
    h.assert_true("multihunk: cursor on hunk 2 (not skipped to hunk 3)",
      ct.cfile == h2.cfile and ct.hunk == h2.hunk)
  end

  -- test 2: focus the long hunk 3 via ]c; its header scrolls to the top line.
  do
    local s = open_m()
    api.nvim_set_option_value("scrolloff", 0, { win = s.win })
    local hs = hunk_headers(s)
    -- park on hunk 2, then ]c forward to hunk 3 (long, taller than the window).
    api.nvim_win_set_cursor(s.win, { hs[2] + 1, 0 })
    s:next_hunk()
    local h3 = hs[3]
    h.assert_eq("multihunk: ]c lands on hunk 3 header", s:cursor_row(), h3)
    local topline = api.nvim_win_call(s.win, function()
      return vim.fn.winsaveview().topline
    end)
    h.assert_eq("multihunk: hunk 3 header scrolled to top", topline - 1, h3)
  end
end

-- Stage 2 — canonical resolver: the file-header glyph and the seen-section
-- placement are now the same computation, so marking a hunk's changed lines
-- (with context lines left untouched) makes the file header agree it is seen.
do
  local s = open({ scope = "commits", state_dir = vim.fn.tempname() })
  -- c2 has two files (f.txt + g.txt), so it stays expanded after we mark only
  -- f.txt; that keeps the f.txt header visible to read its glyph.
  local frow = find_row(s, function(_, line, t)
    return t and t.commit == 2 and t.file and not t.hunk and line:find("f.txt", 1, true)
  end)
  h.assert_true("resolver: found c2 f.txt header", frow ~= nil)
  local commit = s.commits[2]
  local file
  for _, f in ipairs(commit.files) do
    if f.path == "f.txt" then file = f end
  end
  h.assert_true("resolver: file_seen false before mark", not s:file_seen(commit, file))
  s:toggle_seen(frow)
  h.assert_true("resolver: file_seen true after marking changed lines",
    s:file_seen(commit, file))
  local _, fline = find_row(s, function(_, line, t)
    return t and t.commit == 2 and t.file and not t.hunk and line:find("f.txt", 1, true)
  end)
  h.assert_true("resolver: f.txt header glyph agrees (✓)", fline:find("✓", 1, true) ~= nil)
  -- Placement ⇔ predicate: every rendered hunk row's section equals hunk_seen.
  local n = api.nvim_buf_line_count(s.buf)
  local agree = true
  for row = 0, n - 1 do
    local t = s.row_map[row]
    if t and t.commit and t.file and t.hunk and not t.line and not t.marker then
      local c = s.commits[t.commit]
      local cf = c.files[t.file]
      local seen = s:hunk_seen(cf.hunks[t.hunk], cf.path, s:commit_owner(c))
      if seen ~= (t.sec == "seen") then agree = false end
    end
  end
  h.assert_true("resolver: placement ⇔ hunk_seen for every hunk row", agree)
end
-- Stage 2 — commit-scope deletion-only hunk participates: a hunk that only
-- removes a line (no add lines) is markable seen and tucks into the seen
-- section; its del identity persists in the commit's pre-image coords.
do
  local dr = testutil.make_repo({
    { msg = "base", files = { ["d.txt"] = "a\nb\nc\n" } },
    { msg = "c1: delete b", files = { ["d.txt"] = "a\nc\n" } },
  })
  local function rund(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = dr.root, env = dr.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = dr.shas[1], target = dr.shas[2], repo_root = dr.root, run = rund,
    open_window = false, state_dir = vim.fn.tempname(), scope = "commits",
  })
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("del-hunk: shows -b deletion", joined:find("\n-b", 1, true) ~= nil)
  h.assert_true("del-hunk: starts unseen", joined:find(" seen", 1, true) == nil)
  local frow = find_row(s, function(_, line, t)
    return t and t.commit == 1 and t.file and not t.hunk and line:find("d.txt", 1, true)
  end)
  s:toggle_seen(frow)
  local jseen = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("del-hunk: marking moves it to the seen section",
    jseen:find(" seen", 1, true) ~= nil)
  h.assert_true("del-hunk: del identity persisted in pre-image coords",
    #s.store:seen_del_ranges(dr.shas[2], "d.txt") > 0)
end
-- Stage 2 — per-line committed-vs-dirty identity: in a file with a committed
-- edit plus an uncommitted edit, the committed add line keeps its (sha, lnum)
-- identity while only the edited line falls back to a content hash.
do
  local wm = testutil.make_repo({
    { msg = "base", files = { ["m.txt"] = "a\nb\nc\nd\n" } },
    { msg = "c1: b->B", files = { ["m.txt"] = "a\nB\nc\nd\n" } },
  })
  local f = assert(io.open(wm.root .. "/m.txt", "w"))
  f:write("a\nB\nc\nD\n") -- uncommitted edit of line 4
  f:close()
  local function runwm(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = wm.root, env = wm.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = wm.shas[1], target = glean.WORKTREE, repo_root = wm.root, run = runwm,
    open_window = false, state_dir = vim.fn.tempname(), -- combined scope
  })
  local cf = s.combined_files[1]
  local owner = s:combined_owner(cf.path)
  local function id_for(text)
    for _, hunk in ipairs(cf.hunks) do
      for _, dl in ipairs(hunk.lines) do
        if dl.kind == "add" and dl.text == text then
          return s:line_identity(dl, cf.path, owner)
        end
      end
    end
  end
  local bid = id_for("B")
  local did = id_for("D")
  h.assert_true("identity: committed B is line-addressed", bid ~= nil and bid.kind == "add")
  h.assert_eq("identity: committed B owned by c1", bid.sha, wm.shas[2])
  h.assert_true("identity: dirty D is content-addressed", did ~= nil and did.kind == "wt")
end
-- Stage 4 — cross-scope del-line identity: a deletion marked seen in commit
-- scope shows as seen in combined scope, because both resolve to the immutable
-- (remover_sha, old_lnum).
do
  local dr = testutil.make_repo({
    { msg = "base", files = { ["d.txt"] = "a\nb\nc\n" } },
    { msg = "c1: delete b", files = { ["d.txt"] = "a\nc\n" } },
  })
  local function rund(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = dr.root, env = dr.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local sdir = vim.fn.tempname()
  local sc = glean.open({
    base = dr.shas[1], target = dr.shas[2], repo_root = dr.root, run = rund,
    open_window = false, state_dir = sdir, scope = "commits",
  })
  local frow = find_row(sc, function(_, line, t)
    return t and t.commit == 1 and t.file and not t.hunk and line:find("d.txt", 1, true)
  end)
  sc:toggle_seen(frow)
  local s = glean.open({
    base = dr.shas[1], target = dr.shas[2], repo_root = dr.root, run = rund,
    open_window = false, state_dir = sdir, -- combined scope
  })
  local cf = s.combined_files[1]
  local owner = s:combined_owner(cf.path)
  local found, seen
  for _, hunk in ipairs(cf.hunks) do
    for _, dl in ipairs(hunk.lines) do
      if dl.kind == "del" and dl.text == "b" then
        found = true
        local id = s:line_identity(dl, cf.path, owner)
        seen = id ~= nil and id.kind == "del" and id.sha == dr.shas[2] and s:line_seen(id)
      end
    end
  end
  h.assert_true("xscope del: found del line in combined", found)
  h.assert_true("xscope del: combined del resolves to remover sha & is seen", seen)
end

-- Stage 4 — a worktree-only deletion has no committed remover, so it is
-- content-addressed (kind "wt") and markable/persistent under WORKTREE.
do
  local wr = testutil.make_repo({
    { msg = "base", files = { ["w.txt"] = "x\ny\nz\n" } },
  })
  local f = assert(io.open(wr.root .. "/w.txt", "w"))
  f:write("x\nz\n") -- uncommitted deletion of y
  f:close()
  local function runwr(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = wr.root, env = wr.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = wr.shas[1], target = glean.WORKTREE, repo_root = wr.root, run = runwr,
    open_window = false, state_dir = vim.fn.tempname(), -- combined scope
  })
  local cf
  for _, c in ipairs(s.combined_files) do
    if c.path == "w.txt" then cf = c end
  end
  h.assert_true("wt del: found w.txt", cf ~= nil)
  local owner = s:combined_owner(cf.path)
  local did
  for _, hunk in ipairs(cf.hunks) do
    for _, dl in ipairs(hunk.lines) do
      if dl.kind == "del" and dl.text == "y" then
        did = s:line_identity(dl, cf.path, owner)
      end
    end
  end
  h.assert_true("wt del: y is content-addressed", did ~= nil and did.kind == "wt")
  h.assert_true("wt del: starts unseen", not s:line_seen(did))
  s.store:mark({ did })
  h.assert_true("wt del: markable & persists", s:line_seen(did))
end

-- Stage 4 — deterministic first-remover: a line text removed by several commits
-- resolves to the first remover in stack (chronological) order.
do
  local mr = testutil.make_repo({
    { msg = "base", files = { ["t.txt"] = "x\nkeep\n" } },
    { msg = "c1: delete x", files = { ["t.txt"] = "keep\n" } },
    { msg = "c2: re-add x", files = { ["t.txt"] = "x\nkeep\n" } },
    { msg = "c3: delete x again", files = { ["t.txt"] = "keep\n" } },
  })
  local function runmr(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = mr.root, env = mr.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = mr.shas[1], target = mr.shas[4], repo_root = mr.root, run = runmr,
    open_window = false, state_dir = vim.fn.tempname(), -- combined scope
  })
  local r = s:del_attribution("t.txt")[1]
  h.assert_true("del dup: resolves", r ~= nil)
  h.assert_eq("del dup: deleter of base line is c1", r.sha, mr.shas[2])
end

-- Stage 5 invariants — locked as tests.
-- (a) No-op mark: marking an already-seen unit performs zero shard writes.
-- (b) No foreign-shard writes: a mark only touches the owning in-range commit
--     shards (and WORKTREE), never an out-of-range/base shard.
-- (c) Round-trip: after a seen action, a re-render places the acted unit in the
--     section the action intended.
do
  local s = open({ scope = "commits", state_dir = vim.fn.tempname() })

  -- Instrument save_commit to record which shards are written. c2 has two files
  -- (f.txt + g.txt), so marking only f.txt keeps the commit expanded and its
  -- f.txt header visible to read the glyph.
  local writes = {}
  local orig_save = s.store.save_commit
  s.store.save_commit = function(self, sha)
    writes[#writes + 1] = sha
    return orig_save(self, sha)
  end

  local function frow()
    return find_row(s, function(_, line, t)
      return t and t.commit == 2 and t.file and not t.hunk and line:find("f.txt", 1, true)
    end)
  end

  local commit, file = s.commits[2], nil
  for _, f in ipairs(commit.files) do
    if f.path == "f.txt" then file = f end
  end

  -- (c) Round-trip: mark f.txt in c2; it lands in the seen section and the glyph
  -- agrees, and only c2's shard was written.
  s:toggle_seen(frow())
  h.assert_true("inv: marked unit renders seen", s:file_seen(commit, file))
  local _, fline = find_row(s, function(_, line, t)
    return t and t.commit == 2 and t.file and not t.hunk and line:find("f.txt", 1, true)
  end)
  h.assert_true("inv: marked unit glyph ✓", fline:find("✓", 1, true) ~= nil)

  -- (b) No foreign-shard writes: only c2's sha (repo.shas[3]) was written; the
  -- base sha (repo.shas[1]) and c1 (repo.shas[2]) were not.
  local only_acted = true
  for _, sha in ipairs(writes) do
    if sha ~= repo.shas[3] then only_acted = false end
  end
  h.assert_true("inv: mark wrote a shard", #writes > 0)
  h.assert_true("inv: no foreign-shard writes (only c2)", only_acted)

  s.store.save_commit = orig_save
end

-- Stage 5 invariant — marking an already-seen unit changes nothing. Re-marking a
-- hunk's identities (all already seen) leaves the shard byte-identical, and the
-- toggle layer filters such redundant marks to an empty change set so no
-- save_commit is issued.
do
  local s = open({ scope = "commits", state_dir = vim.fn.tempname() })
  local commit = s.commits[1]
  local sha = commit.sha
  local function encode_shard()
    return vim.json.encode(s.store.data[sha] or { files = {} })
  end

  -- Gather every changed-line identity in c1 and mark them seen.
  local ids = {}
  for _, f in ipairs(commit.files) do
    for _, hunk in ipairs(f.hunks) do
      for _, id in ipairs(s:changed_lines(hunk, f.path, s:commit_owner(commit))) do
        ids[#ids + 1] = id
      end
    end
  end
  s.store:mark(ids)
  local marked = encode_shard()

  -- Re-marking the same (already-seen) identities is byte-identical: a redundant
  -- mark changes nothing in the store.
  s.store:mark(ids)
  h.assert_eq("inv: redundant store mark is byte-identical", encode_shard(), marked)

  -- And the toggle layer's change filter yields zero: none of the ids flips.
  local changed = {}
  for _, id in ipairs(ids) do
    if not s.store:is_seen(id) then changed[#changed + 1] = id end
  end
  h.assert_eq("inv: no identity changes when all already seen", #changed, 0)
end

-- compute_ancestry (pure): header rows are classified into the correct level,
-- body rows inherit the running ancestry, and a shallower header clears deeper
-- levels. Synthetic row_map fixtures cover both scopes.
do
  -- commits scope: mode, commit, file, seen-section, hunk, line, marker,
  -- unseen-section, hunk, line.
  local rm = {
    [0] = {},
    [1] = { commit = 1 },
    [2] = { commit = 1, file = 1 },
    [3] = { commit = 1, file = 1, seen = true },
    [4] = { commit = 1, file = 1, hunk = 1, sec = "seen" },
    [5] = { commit = 1, file = 1, hunk = 1, sec = "seen", line = 1 },
    [6] = { commit = 1, file = 1, hunk = 1, sec = "seen", marker = {} },
    [7] = { commit = 1, file = 1, unseen = true },
    [8] = { commit = 1, file = 1, hunk = 2, sec = "unseen" },
    [9] = { commit = 1, file = 1, hunk = 2, sec = "unseen", line = 1 },
  }
  local anc = glean.compute_ancestry(rm, 10)
  local function chk(name, row, exp)
    h.assert_eq(name, vim.inspect(anc[row]), vim.inspect(exp))
  end
  chk("anc: mode header has no ancestry", 0, {})
  chk("anc: commit header carries only commit", 1, { commit_row = 1 })
  chk("anc: file header carries commit+file", 2,
    { commit_row = 1, file_row = 2 })
  chk("anc: seen section carries commit+file+sec", 3,
    { commit_row = 1, file_row = 2, sec_row = 3 })
  chk("anc: hunk header carries full chain", 4,
    { commit_row = 1, file_row = 2, sec_row = 3, hunk_row = 4 })
  chk("anc: body line inherits running ancestry", 5,
    { commit_row = 1, file_row = 2, sec_row = 3, hunk_row = 4 })
  chk("anc: marker row pins through its hunk (body, not header)", 6,
    { commit_row = 1, file_row = 2, sec_row = 3, hunk_row = 4 })
  chk("anc: unseen section clears the prior hunk", 7,
    { commit_row = 1, file_row = 2, sec_row = 7 })
  chk("anc: second hunk header under unseen", 8,
    { commit_row = 1, file_row = 2, sec_row = 7, hunk_row = 8 })
  chk("anc: line under second hunk", 9,
    { commit_row = 1, file_row = 2, sec_row = 7, hunk_row = 8 })

  -- combined scope: no commit level; cfile is the file header.
  local cm = {
    [0] = {},
    [1] = { cfile = 1 },
    [2] = { cfile = 1, unseen = true },
    [3] = { cfile = 1, hunk = 1, sec = "unseen" },
    [4] = { cfile = 1, hunk = 1, sec = "unseen", line = 1 },
  }
  local canc = glean.compute_ancestry(cm, 5)
  h.assert_eq("anc/combined: cfile header has no commit level",
    vim.inspect(canc[1]), vim.inspect({ file_row = 1 }))
  h.assert_eq("anc/combined: line inherits file+sec+hunk, no commit",
    vim.inspect(canc[4]),
    vim.inspect({ file_row = 1, sec_row = 2, hunk_row = 3 }))
end

-- compute_pinned (pure): from an ancestry table and the top visible row w0,
-- the ordered pinned list [commit, file, sec, hunk] filtered to rows < w0.
do
  local rm = {
    [0] = {},
    [1] = { commit = 1 },
    [2] = { commit = 1, file = 1 },
    [3] = { commit = 1, file = 1, seen = true },
    [4] = { commit = 1, file = 1, hunk = 1, sec = "seen" },
    [5] = { commit = 1, file = 1, hunk = 1, sec = "seen", line = 1 },
    [6] = { commit = 1, file = 1, hunk = 1, sec = "seen", marker = {} },
    [7] = { commit = 1, file = 1, unseen = true },
    [8] = { commit = 1, file = 1, hunk = 2, sec = "unseen" },
    [9] = { commit = 1, file = 1, hunk = 2, sec = "unseen", line = 1 },
  }
  local anc = glean.compute_ancestry(rm, 10)
  local function chk(name, w0, exp)
    h.assert_eq(name, vim.inspect(glean.compute_pinned(anc, w0)),
      vim.inspect(exp))
  end
  chk("pin: top-of-buffer mode header has no float", 0, {})
  chk("pin: on commit header, nothing above it", 1, {})
  chk("pin: on file header, commit pins above", 2, { 1 })
  chk("pin: just below hunk header pins full chain", 5, { 1, 2, 3, 4 })
  chk("pin: on a header row excludes itself (still visible)", 4, { 1, 2, 3 })
  chk("pin: marker row pins through its hunk", 6, { 1, 2, 3, 4 })
  chk("pin: line under second hunk after section change", 9,
    { 1, 2, 7, 8 })
  chk("pin: w0 past end of buffer has no float", 99, {})

  -- combined scope: at most 3 pinned rows (no commit header).
  local cm = {
    [0] = {},
    [1] = { cfile = 1 },
    [2] = { cfile = 1, unseen = true },
    [3] = { cfile = 1, hunk = 1, sec = "unseen" },
    [4] = { cfile = 1, hunk = 1, sec = "unseen", line = 1 },
  }
  local canc = glean.compute_ancestry(cm, 5)
  h.assert_eq("pin/combined: line under hunk pins file+sec+hunk, no commit",
    vim.inspect(glean.compute_pinned(canc, 4)), vim.inspect({ 1, 2, 3 }))
end

-- Stage 3 — sticky header float: scrolling past a tall hunk's headers pins the
-- enclosing commit/file/section/hunk rows in a top-anchored float; the float is
-- reused, tracks the topline, collapses to nothing at the top, and tears down
-- when the chain empties or the window closes.
do
  local function lines_n(overrides, n)
    local t = {}
    for i = 1, n do t[i] = overrides[i] or ("line" .. i) end
    return table.concat(t, "\n") .. "\n"
  end
  local tgt = {}
  for i = 10, 70 do tgt[i] = "line" .. i .. "_Z" end
  local srepo = testutil.make_repo({
    { msg = "base", files = { ["s.txt"] = lines_n({}, 80) } },
    { msg = "edit a tall block", files = { ["s.txt"] = lines_n(tgt, 80) } },
  })
  local function srun(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = srepo.root, env = srepo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end
  local s = glean.open({
    base = srepo.shas[1], target = srepo.shas[2], repo_root = srepo.root, run = srun,
    open_window = true, state_dir = vim.fn.tempname(), scope = "commits",
  })
  api.nvim_set_option_value("scrolloff", 0, { win = s.win })
  api.nvim_win_set_height(s.win, 8)

  -- locate the hunk header row and a body line ~30 rows below it.
  local hunk_row
  local n = api.nvim_buf_line_count(s.buf)
  for row = 0, n - 1 do
    local t = s.row_map[row]
    if t and t.hunk and not t.line and not t.marker and t.sec ~= "seen" then
      hunk_row = row
      break
    end
  end
  h.assert_true("sticky: found a hunk header", hunk_row ~= nil)
  local body_row = hunk_row + 30

  -- top of buffer: empty chain, no float.
  api.nvim_win_set_cursor(s.win, { 1, 0 })
  api.nvim_win_call(s.win, function() vim.fn.winrestview({ topline = 1, lnum = 1 }) end)
  s:update_sticky()
  h.assert_true("sticky: no float at top of buffer",
    not (s._sticky_win and api.nvim_win_is_valid(s._sticky_win)))

  -- scroll so the hunk's headers leave the viewport.
  api.nvim_win_set_cursor(s.win, { body_row + 1, 0 })
  api.nvim_win_call(s.win, function()
    vim.fn.winrestview({ topline = body_row + 1, lnum = body_row + 1 })
  end)
  s:update_sticky()
  h.assert_true("sticky: float shown mid-hunk",
    s._sticky_win and api.nvim_win_is_valid(s._sticky_win))
  local pinned = glean.compute_pinned(s.ancestry, body_row)
  h.assert_true("sticky: full chain pinned (commit/file/sec/hunk)", #pinned == 4)
  local fl = api.nvim_buf_get_lines(s._sticky_buf, 0, -1, false)
  h.assert_eq("sticky: one float line per pinned header", #fl, #pinned)
  for i, row in ipairs(pinned) do
    local src = api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1]
    h.assert_eq("sticky: float line " .. i .. " is its header",
      fl[i], src)
  end

  -- reused: scrolling again keeps the same float window id.
  local win0 = s._sticky_win
  api.nvim_win_set_cursor(s.win, { body_row, 0 })
  api.nvim_win_call(s.win, function()
    vim.fn.winrestview({ topline = body_row, lnum = body_row })
  end)
  s:update_sticky()
  h.assert_eq("sticky: float window reused across updates", s._sticky_win, win0)

  -- back to the top: chain empties, float closes.
  api.nvim_win_set_cursor(s.win, { 1, 0 })
  api.nvim_win_call(s.win, function() vim.fn.winrestview({ topline = 1, lnum = 1 }) end)
  s:update_sticky()
  h.assert_true("sticky: float closed back at top",
    not (s._sticky_win and api.nvim_win_is_valid(s._sticky_win)))

  -- closing the glean window tears the float down.
  api.nvim_win_set_cursor(s.win, { body_row + 1, 0 })
  api.nvim_win_call(s.win, function()
    vim.fn.winrestview({ topline = body_row + 1, lnum = body_row + 1 })
  end)
  s:update_sticky()
  h.assert_true("sticky: float reopened before close",
    s._sticky_win and api.nvim_win_is_valid(s._sticky_win))
  -- a second real window so closing the glean window isn't closing the last one.
  vim.cmd("botright new")
  api.nvim_win_close(s.win, true)
  h.assert_true("sticky: float gone after window close",
    not (s._sticky_win and api.nvim_win_is_valid(s._sticky_win)))
end

h.finish()
h.finish()
