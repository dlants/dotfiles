-- Tier 2 tests for glean.git against a hermetic git fixture. Run with:
--   nvim -l nvim/lua/glean/git_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local git_mod = require("glean.git")
local testutil = require("glean.testutil")
local h = testutil.new()

-- A multi-commit fixture: base on main, a branch with several commits editing
-- overlapping regions of the same file plus an added file.
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
local git = git_mod.new({
  repo_root = repo.root,
  run = function(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = repo.root, env = repo.env, text = true }):wait()
    return { code = res.code, stdout = res.stdout, stderr = res.stderr }
  end,
})

-- commits(): the two commits beyond base, chronological.
do
  local commits = git:commits(base, target)
  h.assert_eq("commits: count", #commits, 2)
  h.assert_eq("commits: first sha", commits[1].sha, repo.shas[2])
  h.assert_eq("commits: first summary", commits[1].summary, "c1: edit two")
  h.assert_eq("commits: second sha", commits[2].sha, repo.shas[3])
end

-- commit_diff(): c1 only touched f.txt's "two" -> "TWO".
do
  local files = git:commit_diff(repo.shas[2])
  h.assert_eq("commit_diff: one file", #files, 1)
  h.assert_eq("commit_diff: path", files[1].path, "f.txt")
  local adds = {}
  for _, l in ipairs(files[1].hunks[1].lines) do
    if l.kind == "add" then adds[#adds + 1] = l end
  end
  h.assert_eq("commit_diff: one add", #adds, 1)
  h.assert_eq("commit_diff: add text", adds[1].text, "TWO")
  h.assert_eq("commit_diff: add new_lnum", adds[1].new_lnum, 2)
end

-- combined_diff(): net of c1+c2 over base -> two files (f.txt, g.txt).
do
  local files = git:combined_diff(base, target)
  h.assert_eq("combined: two files", #files, 2)
  local by_path = {}
  for _, f in ipairs(files) do by_path[f.path] = f end
  h.assert_true("combined: has f.txt", by_path["f.txt"] ~= nil)
  h.assert_true("combined: has g.txt", by_path["g.txt"] ~= nil)
  h.assert_eq("combined: g.txt is add", by_path["g.txt"].kind, "add")
  -- f.txt net: two->TWO and three->THREE both present as adds.
  local addtext = {}
  for _, hunk in ipairs(by_path["f.txt"].hunks) do
    for _, l in ipairs(hunk.lines) do
      if l.kind == "add" then addtext[l.text] = true end
    end
  end
  h.assert_true("combined: f.txt has TWO add", addtext["TWO"])
  h.assert_true("combined: f.txt has THREE add", addtext["THREE"])
end

-- range_diff() restricted to a path mirrors combined for that file alone.
do
  local files = git:range_diff(base, target, "g.txt")
  h.assert_eq("range_diff path: one file", #files, 1)
  h.assert_eq("range_diff path: g.txt", files[1].path, "g.txt")
end

-- show(): contents of f.txt at the base ref.
do
  local out = git:show(base, "f.txt")
  h.assert_eq("show: base f.txt", out, "one\ntwo\nthree\n")
end

-- blame() returns porcelain output naming the owning sha for a line.
do
  local out = git:blame(target, "f.txt", 2, 2)
  h.assert_true("blame: nonempty", out ~= nil and #out > 0)
  h.assert_true("blame: names c1 sha", out:find(repo.shas[2], 1, true) ~= nil)
end

-- rev_parse resolves a ref to a sha.
do
  h.assert_eq("rev_parse: target", git:rev_parse(target), target)
end

h.finish()
