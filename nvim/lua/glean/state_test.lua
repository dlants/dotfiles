-- Tier 1 tests for glean.state: pure range math plus JSON shard round-trips in
-- a tempname() dir. Run with:
--   nvim -l nvim/lua/glean/state_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local state = require("glean.state")
local testutil = require("glean.testutil")
local h = testutil.new()

local function range_str(ranges)
  local parts = {}
  for _, r in ipairs(ranges) do parts[#parts + 1] = r[1] .. "-" .. r[2] end
  return table.concat(parts, ",")
end

-- merge: overlapping and adjacent ranges coalesce; disjoint stay split.
do
  h.assert_eq("merge: adjacent", range_str(state.merge({ { 1, 3 }, { 4, 6 } })), "1-6")
  h.assert_eq("merge: overlap", range_str(state.merge({ { 1, 5 }, { 3, 8 } })), "1-8")
  h.assert_eq("merge: disjoint", range_str(state.merge({ { 5, 6 }, { 1, 2 } })), "1-2,5-6")
end

-- add / remove.
do
  local r = state.add({ { 1, 2 } }, { 5, 6 })
  h.assert_eq("add: disjoint", range_str(r), "1-2,5-6")
  r = state.add(r, { 3, 4 })
  h.assert_eq("add: bridges", range_str(r), "1-6")
  r = state.remove(r, { 3, 3 })
  h.assert_eq("remove: splits", range_str(r), "1-2,4-6")
  r = state.remove({ { 1, 10 } }, { 1, 10 })
  h.assert_eq("remove: whole", range_str(r), "")
end

-- covers / range_covered.
do
  local r = { { 1, 3 }, { 7, 9 } }
  h.assert_true("covers: inside", state.covers(r, 8))
  h.assert_true("covers: gap", not state.covers(r, 5))
  h.assert_true("range_covered: full", state.range_covered({ { 1, 10 } }, { 3, 7 }))
  h.assert_true("range_covered: split fails", not state.range_covered({ { 1, 4 }, { 6, 10 } }, { 3, 7 }))
end

-- Shard round-trip: seen ranges and stacked comments persist per-sha; load of a
-- never-seen sha is empty; unmatched commit loads clean.
do
  local dir = vim.fn.tempname()
  local s = state.new({ dir = dir })
  s:load({ "shaA", "shaB" })
  s:mark_seen("shaA", "f.txt", { 2, 4 })
  s:mark_seen("shaA", "f.txt", { 10, 10 })
  s:add_comment("shaA", "f.txt", 3, "first")
  s:add_comment("shaA", "f.txt", 3, "second")
  s:add_comment("shaA", "f.txt", 7, "other")
  s:save_commit("shaA")

  local s2 = state.new({ dir = dir })
  s2:load({ "shaA", "shaB" })
  h.assert_eq("roundtrip: seen ranges", range_str(s2:seen_ranges("shaA", "f.txt")), "2-4,10-10")
  local c = s2:comments_at("shaA", "f.txt", 3)
  h.assert_eq("roundtrip: comment count", #c, 2)
  h.assert_eq("roundtrip: comment text", c[1].text, "first")
  h.assert_eq("roundtrip: stacked text", c[2].text, "second")
  h.assert_eq("roundtrip: other line", s2:comments_at("shaA", "f.txt", 7)[1].text, "other")
  h.assert_eq("roundtrip: unseen sha empty", range_str(s2:seen_ranges("shaB", "f.txt")), "")
  h.assert_eq("roundtrip: unmatched lnum empty", #s2:comments_at("shaA", "f.txt", 999), 0)
end

h.finish()
