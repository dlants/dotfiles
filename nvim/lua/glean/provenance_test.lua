-- Tier 1/2 tests for glean.provenance: parse blame porcelain and resolve
-- per-line ownership against a hermetic fixture. Run with:
--   nvim -l nvim/lua/glean/provenance_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local provenance = require("glean.provenance")
local git_mod = require("glean.git")
local testutil = require("glean.testutil")
local h = testutil.new()

-- Tier 1: parse a synthetic blame porcelain blob.
do
  local blob = table.concat({
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 1",
    "author X",
    "summary base",
    "filename f.txt",
    "\tone",
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 2 2 1",
    "previous aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa f.txt",
    "filename f.txt",
    "\tTWO",
  }, "\n")
  local map = provenance.parse_blame(blob)
  h.assert_eq("parse: line1 sha", map[1].sha, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  h.assert_eq("parse: line1 orig", map[1].orig_lnum, 1)
  h.assert_eq("parse: line2 sha", map[2].sha, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
  h.assert_eq("parse: line2 orig", map[2].orig_lnum, 2)
  h.assert_true("parse: metadata ignored", map[3] == nil)
end

-- Tier 2: blame a real fixture, owner of the edited line is c1.
do
  local repo = testutil.make_repo({
    { msg = "base", files = { ["f.txt"] = "one\ntwo\nthree\n" } },
    { msg = "c1", files = { ["f.txt"] = "one\nTWO\nthree\n" } },
  })
  local git = git_mod.new({
    repo_root = repo.root,
    run = function(args)
      local cmd = { "git" }
      for _, a in ipairs(args) do cmd[#cmd + 1] = a end
      local r = vim.system(cmd, { cwd = repo.root, env = repo.env, text = true }):wait()
      return { code = r.code, stdout = r.stdout, stderr = r.stderr }
    end,
  })
  local map = provenance.parse_blame(git:blame(repo.shas[2], "f.txt"))
  h.assert_eq("fixture: line2 owned by c1", map[2].sha, repo.shas[2])
  h.assert_eq("fixture: line1 owned by base", map[1].sha, repo.shas[1])
  h.assert_eq("fixture: line2 orig_lnum", map[2].orig_lnum, 2)
end

h.finish()
