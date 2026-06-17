-- Repro: marking seen in the COMBINED scope of a dirty (work-tree) review.
-- `:Glean HEAD` opens base=HEAD, target=WORKTREE. The commit scope can mark
-- the floating "uncommitted changes" commit seen, but the combined scope is
-- reported as not markable. Run with:
--   nvim -l nvim/lua/glean/dirty_combined_test.lua
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
})
local base = "HEAD"

-- Uncommitted edit: change "two" -> "TWO" in the work tree (not committed).
do
  local f = assert(io.open(repo.root .. "/f.txt", "w"))
  f:write("one\nTWO\nthree\n")
  f:close()
end

local function inject_run(args)
  local cmd = { "git" }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local res = vim.system(cmd, { cwd = repo.root, env = repo.env, text = true }):wait()
  return { code = res.code, stdout = res.stdout, stderr = res.stderr }
end

local state_dir = vim.fn.tempname()
local function open(scope)
  return glean.open({
    base = base,
    target = glean.WORKTREE,
    repo_root = repo.root,
    run = inject_run,
    open_window = false,
    state_dir = state_dir,
    scope = scope,
  })
end

-- Find a body line row in the combined buffer for the +TWO add line.
local function find_add_row(s, text)
  local n = api.nvim_buf_line_count(s.buf)
  for row = 0, n - 1 do
    local t = s.row_map[row]
    if t and t.line and t.cfile then
      local line = api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1]
      if line and line:find(text, 1, true) then return row end
    end
  end
end

-- Combined scope: the +TWO add line should resolve to a seen identity, and
-- toggling its hunk seen should persist (hunk_seen -> true after).
do
  local s = open("combined")
  local row = find_add_row(s, "TWO")
  h.assert_true("combined: found +TWO row", row ~= nil)

  local cf = s.combined_files[s.row_map[row].cfile]
  local hunk = cf.hunks[s.row_map[row].hunk]
  local id = s:row_identity(s.row_map[row])
  h.assert_true("combined: +TWO has a seen identity", id ~= nil)

  s:toggle_seen(row)
  h.assert_true("combined: hunk seen after toggle",
    s:hunk_seen(hunk, cf.path, s:combined_owner(cf.path)))

  -- A live poll rebuilds the model + reloads the store from disk. The mark must
  -- survive (it is content-addressed under the WORKTREE shard).
  s:reload()
  h.assert_true("combined: identity still seen after reload", s.store:is_seen(id))
end

-- Same flow but mark via the file *header* row (no hunk index): a cfile header
-- toggle must mark every changed line of the file seen in combined dirty scope.
do
  local state_dir2 = vim.fn.tempname()
  local s = glean.open({
    base = base, target = glean.WORKTREE, repo_root = repo.root,
    run = inject_run, open_window = false, state_dir = state_dir2, scope = "combined",
  })
  local function header_row()
    local n = api.nvim_buf_line_count(s.buf)
    for r = 0, n - 1 do
      local t = s.row_map[r]
      if t and t.cfile and not t.hunk and not t.line then return r end
    end
  end
  local hr = header_row()
  h.assert_true("header: found f.txt header row", hr ~= nil)
  s:toggle_seen(hr)
  local cf = s.combined_files[1]
  local owner = s:combined_owner(cf.path)
  local all_seen = true
  for _, hunk in ipairs(cf.hunks) do
    if not s:hunk_seen(hunk, cf.path, owner) then all_seen = false end
  end
  h.assert_true("header: file seen after header toggle", all_seen)
end

-- Untracked (new) file: it shows up in commit-by-commit scope (attached to the
-- floating "uncommitted changes" commit), but the combined net diff is
-- `git diff HEAD`, which omits untracked files -- so the file is invisible in
-- combined scope and cannot be marked there. This is the reported bug.
do
  local f = assert(io.open(repo.root .. "/new.txt", "w"))
  f:write("alpha\nbeta\n")
  f:close()

  local state_dir3 = vim.fn.tempname()
  -- commit scope: the untracked file is present and markable.
  local sc = glean.open({
    base = "HEAD", target = glean.WORKTREE, repo_root = repo.root,
    run = inject_run, open_window = false, state_dir = state_dir3, scope = "commits",
  })
  local joined_c = table.concat(api.nvim_buf_get_lines(sc.buf, 0, -1, false), "\n")
  h.assert_true("untracked: present in commits scope", joined_c:find("new.txt", 1, true) ~= nil)

  -- combined scope: the untracked file should be present too.
  local s = glean.open({
    base = "HEAD", target = glean.WORKTREE, repo_root = repo.root,
    run = inject_run, open_window = false, state_dir = state_dir3, scope = "combined",
  })
  local joined = table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n")
  h.assert_true("untracked: present in combined scope", joined:find("new.txt", 1, true) ~= nil)

  -- ...and its lines must be markable (content-addressed under WORKTREE).
  local urow
  local n = api.nvim_buf_line_count(s.buf)
  for r = 0, n - 1 do
    local t = s.row_map[r]
    if t and t.line and t.cfile then
      local cf = s.combined_files[t.cfile]
      if cf.path == "new.txt" then urow = r; break end
    end
  end
  h.assert_true("untracked: found a new.txt body row", urow ~= nil)
  local uid = s:row_identity(s.row_map[urow])
  h.assert_true("untracked: row has a seen identity", uid ~= nil)
  s:toggle_seen(urow)
  h.assert_true("untracked: identity seen after toggle", uid ~= nil and s.store:is_seen(uid))
end

h.finish()
