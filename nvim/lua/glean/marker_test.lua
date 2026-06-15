-- Tier 1 unit tests for glean.init marker helpers: hunk_marker_runs and the
-- content-addressed marker keys. Run with:
--   nvim -l nvim/lua/glean/marker_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local glean = require("glean.init")
local testutil = require("glean.testutil")
local h = testutil.new()

local I = glean._internal

-- A fake predicate whose seen set is a set of line texts. The real renderer
-- passes a closure over the line-identity store; here we key on text so both
-- adds and deletions can be marked seen.
local function fake_seen(seen)
  return function(dl) return seen[dl.text] == true end
end
-- Hunk: lines 1..8 where lines map to new_lnum 1..7 (line 5 is a deletion,
-- no new_lnum).
local hunk = {
  lines = {
    { kind = "context", text = "l1", new_lnum = 1 },
    { kind = "add", text = "l2", new_lnum = 2 },
    { kind = "add", text = "l3", new_lnum = 3 },
    { kind = "add", text = "l4", new_lnum = 4 },
    { kind = "del", text = "gone" },
    { kind = "context", text = "l5", new_lnum = 5 },
    { kind = "add", text = "l7", new_lnum = 7 },
    { kind = "context", text = "l8", new_lnum = 8 },
  },
}
local runs = I.hunk_marker_runs(hunk, fake_seen({ l2 = true, l3 = true, l4 = true, l7 = true }))
h.assert_eq("two runs", #runs, 2)
h.assert_eq("run1 lo", runs[1].lo, 2)
h.assert_eq("run1 hi_line", runs[1].hi_line, 4)
h.assert_eq("run1 lnum_lo", runs[1].lnum_lo, 2)
h.assert_eq("run1 lnum_hi", runs[1].lnum_hi, 4)
h.assert_eq("run1 n", runs[1].n, 3)
h.assert_eq("run1 texts", table.concat(runs[1].texts, ","), "l2,l3,l4")
h.assert_eq("run2 lo", runs[2].lo, 7)
h.assert_eq("run2 n", runs[2].n, 1)
h.assert_eq("run2 lnum_lo", runs[2].lnum_lo, 7)
-- A seen deletion joins a contiguous run with an adjacent seen add.
local with_del = I.hunk_marker_runs(hunk, fake_seen({ l4 = true, gone = true }))
h.assert_eq("add+del coalesce -> one run", #with_del, 1)
h.assert_eq("add+del run texts", table.concat(with_del[1].texts, ","), "l4,gone")
h.assert_eq("add+del run n", with_del[1].n, 2)
-- A pure-deletion run collapses on its own (lnum bounds are nil).
local del_only = I.hunk_marker_runs(hunk, fake_seen({ gone = true }))
h.assert_eq("del-only -> one run", #del_only, 1)
h.assert_eq("del-only texts", table.concat(del_only[1].texts, ","), "gone")
h.assert_true("del-only lnum_lo nil", del_only[1].lnum_lo == nil)
-- An unseen changed line in the middle breaks the run.
local broken = I.hunk_marker_runs(hunk, fake_seen({ l2 = true, l4 = true }))
h.assert_eq("gap breaks run -> two runs", #broken, 2)
-- No seen lines -> no runs.
h.assert_eq("no seen -> no runs", #I.hunk_marker_runs(hunk, fake_seen({})), 0)
-- Marker keys are content-addressed and scope-prefixed.
local k1 = I.marker_key("f.txt", { "a", "b" })
local k2 = I.marker_key("f.txt", { "a", "b" })
local k3 = I.marker_key("f.txt", { "a", "c" })
h.assert_eq("marker_key stable", k1, k2)
h.assert_true("marker_key content-sensitive", k1 ~= k3)
h.assert_true("marker_key prefix", k1:sub(1, 3) == "mk:")
h.assert_true("cmarker_key prefix", I.cmarker_key("f.txt", { "a" }):sub(1, 4) == "cmk:")
h.assert_true("marker vs cmarker differ", I.marker_key("f.txt", { "a" }) ~= I.cmarker_key("f.txt", { "a" }))

h.finish()
