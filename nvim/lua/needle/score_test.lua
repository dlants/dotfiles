-- Tests for needle.score.
--
-- Run from the repo root with:
--   nvim -l nvim/lua/needle/score_test.lua
--
-- Uses neovim's bundled LuaJIT, no extra dependencies. Exits 0 on success,
-- 1 on any failure.

-- Resolve sibling modules without depending on the user's runtimepath.
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir   = this_script:match("(.+)/[^/]+$") or "."
local lua_root   = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local score = require("needle.score")

-- ============================================================================
-- Tiny test harness
-- ============================================================================

local pass, fail = 0, 0
local failures = {}

local function record_fail(name, detail)
  fail = fail + 1
  failures[#failures + 1] = { name = name, detail = detail }
end

local function array_eq(a, b)
  if a == nil or b == nil then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function arr_str(t)
  if t == nil then return "nil" end
  return "[" .. table.concat(t, ",") .. "]"
end

local function assert_eq(name, actual, expected)
  if actual == expected then pass = pass + 1
  else record_fail(name, ("expected %s, got %s"):format(tostring(expected), tostring(actual))) end
end

local function assert_arr(name, actual, expected)
  if array_eq(actual, expected) then pass = pass + 1
  else record_fail(name, ("expected %s, got %s"):format(arr_str(expected), arr_str(actual))) end
end

local function assert_true(name, cond, detail)
  if cond then pass = pass + 1
  else record_fail(name, detail) end
end

local function smatch(needle, haystack)
  return score.score_match(needle, needle:lower(), haystack, haystack:lower())
end

-- ============================================================================
-- Tests
-- ============================================================================

-- Edge cases
do
  local s, pos = smatch("", "anything")
  assert_eq("empty needle returns 0 score", s, 0)
  assert_eq("empty needle returns nil positions", pos, nil)
end

do
  local s = smatch("abcdef", "abc")
  assert_eq("needle longer than haystack returns nil", s, nil)
end

do
  local s = smatch("xyz", "abc")
  assert_eq("non-subsequence returns nil", s, nil)
end

-- DP picks the filename match instead of the early directory match.
-- Old greedy LtR would have chosen [2,6,7]; DP picks [5,6,7].
do
  local s, pos = smatch("bar", "abc/bar.lua")
  assert_true("bar in abc/bar.lua matches", s ~= nil)
  assert_arr("bar lands in filename, not directory", pos, { 5, 6, 7 })
end

-- DP advantage: case-sensitive case_bonus interaction. Old greedy commits 'b'
-- at position 3 (no after-slash bonus); DP picks 'b' at position 5 for the
-- much larger after-slash bonus, even at the cost of a longer span.
do
  local s, pos = smatch("aB", "aab/bar")
  assert_true("aB in aab/bar matches", s ~= nil)
  assert_arr("aB picks after-slash b", pos, { 1, 5 })
end

-- DP advantage: prefer consecutive run after a word boundary over a scattered
-- early match. positions=[1,3] (greedy) vs [5,6] (DP, after _ + consecutive).
do
  local s, pos = smatch("ab", "axb_ab")
  assert_true("ab in axb_ab matches", s ~= nil)
  assert_arr("ab prefers consecutive run after _", pos, { 5, 6 })
end

-- Filename bonus + after-slash bonus stack up: "foo" should score much higher
-- when it sits right after a slash than when it sits at the start of a path.
do
  local s_dir,  _ = smatch("foo", "foo/x.lua")
  local s_file, _ = smatch("foo", "x/foo.lua")
  assert_true("both haystacks match", s_dir ~= nil and s_file ~= nil)
  assert_true("filename match outscores directory match",
    s_file > s_dir,
    ("dir=%s file=%s"):format(tostring(s_dir), tostring(s_file)))
end

-- Ranking via the rank() helper: the better-positioned match comes first.
do
  local results = score.rank("bar", { "abc/foo_bar.lua", "src/bar.lua", "noise.txt" })
  assert_eq("rank returns 2 matches", #results, 2)
  assert_eq("src/bar.lua ranks first", results[1] and results[1].text, "src/bar.lua")
  assert_eq("abc/foo_bar.lua ranks second", results[2] and results[2].text, "abc/foo_bar.lua")
end

-- A non-matching candidate should be dropped from rank() entirely.
do
  local results = score.rank("zzz", { "src/bar.lua", "lib/baz.lua" })
  assert_eq("no matches yields empty result", #results, 0)
end

-- ============================================================================
-- Summary
-- ============================================================================

io.stdout:write(("\n%d passed, %d failed\n"):format(pass, fail))
if fail > 0 then
  io.stdout:write("\nFailures:\n")
  for _, f in ipairs(failures) do
    io.stdout:write(("  - %s: %s\n"):format(f.name, f.detail or ""))
  end
  os.exit(1)
end
