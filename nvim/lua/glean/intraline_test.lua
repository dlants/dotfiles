-- Tier 1 tests for glean.intraline (pure tokenizer + alignment helpers).
-- Run with: nvim -l nvim/lua/glean/intraline_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path
local intraline = require("glean.intraline")
local h = require("glean.testutil").new()

-- Render tokens to a compact { text, col, len } comparison via a joined string.
local function toks_to_str(tokens)
  local parts = {}
  for _, t in ipairs(tokens) do
    parts[#parts + 1] = ("%s@%d+%d"):format(t.text, t.col, t.len)
  end
  return table.concat(parts, "|")
end

-- Word/underscore runs coalesce; punctuation and space are single tokens.
do
  local toks = intraline.tokenize("foo_bar(x) = 1")
  local got = {}
  for _, t in ipairs(toks) do got[#got + 1] = t.text end
  h.assert_eq(
    "tokenize: token texts",
    table.concat(got, "|"),
    "foo_bar|(|x|)| |=| |1"
  )
  h.assert_eq(
    "tokenize: offsets",
    toks_to_str(toks),
    "foo_bar@0+7|(@7+1|x@8+1|)@9+1| @10+1|=@11+1| @12+1|1@13+1"
  )
end

-- Empty string yields no tokens.
do
  h.assert_eq("tokenize: empty", #intraline.tokenize(""), 0)
end

-- A run of digits and letters coalesces into one token.
do
  local toks = intraline.tokenize("abc123")
  h.assert_eq("tokenize: alnum count", #toks, 1)
  h.assert_eq("tokenize: alnum text", toks[1].text, "abc123")
  h.assert_eq("tokenize: alnum col", toks[1].col, 0)
  h.assert_eq("tokenize: alnum len", toks[1].len, 6)
end

-- Consecutive punctuation are individual single-byte tokens.
do
  local toks = intraline.tokenize("->;")
  h.assert_eq("tokenize: punct count", #toks, 3)
  h.assert_eq("tokenize: punct[1]", toks[1].text, "-")
  h.assert_eq("tokenize: punct[2]", toks[2].text, ">")
  h.assert_eq("tokenize: punct[3]", toks[3].text, ";")
  h.assert_eq("tokenize: punct[3] col", toks[3].col, 2)
end

-- Render a segment list to a compact comparison string.
local function segs_to_str(segs)
  local parts = {}
  for _, s in ipairs(segs) do
    parts[#parts + 1] = ("%d:%d"):format(s.start_col, s.end_col)
  end
  return table.concat(parts, "|")
end

-- A one-token substitution highlights only that token on each side.
do
  local r = intraline.align("value = 1", "value = 2")
  h.assert_true("align: sub non-nil", r ~= nil)
  h.assert_eq("align: sub a_segs", segs_to_str(r.a_segs), "8:9")
  h.assert_eq("align: sub b_segs", segs_to_str(r.b_segs), "8:9")
end

-- An inserted word run is a single contiguous segment on the longer side.
do
  local r = intraline.align("f(x)", "f(x, y)")
  h.assert_true("align: insert non-nil", r ~= nil)
  h.assert_eq("align: insert a_segs empty", segs_to_str(r.a_segs), "")
  h.assert_eq("align: insert b_segs", segs_to_str(r.b_segs), "3:6")
end

-- Completely different lines early-terminate to nil.
do
  h.assert_true("align: dissimilar nil", intraline.align("import os", "return None") == nil)
end

-- Identical lines yield empty segment lists (no emphasis).
do
  local r = intraline.align("same line", "same line")
  h.assert_true("align: identical non-nil", r ~= nil)
  h.assert_eq("align: identical a_segs", segs_to_str(r.a_segs), "")
  h.assert_eq("align: identical b_segs", segs_to_str(r.b_segs), "")
end

-- Render a pair list to a compact comparison string.
local function pairs_to_str(pairs_out)
  local parts = {}
  for _, p in ipairs(pairs_out) do
    parts[#parts + 1] = ("%d-%d"):format(p[1], p[2])
  end
  return table.concat(parts, "|")
end

-- Equal-length runs pair index-for-index with no surplus.
do
  local r = intraline.pair_lines({ "a", "b", "c" }, { "x", "y", "z" })
  h.assert_eq("pair_lines: equal pairs", pairs_to_str(r.pairs), "1-1|2-2|3-3")
  h.assert_eq("pair_lines: equal del_unpaired", #r.del_unpaired, 0)
  h.assert_eq("pair_lines: equal add_unpaired", #r.add_unpaired, 0)
end

-- Surplus del lines are left unpaired.
do
  local r = intraline.pair_lines({ "a", "b", "c" }, { "x" })
  h.assert_eq("pair_lines: more del pairs", pairs_to_str(r.pairs), "1-1")
  h.assert_eq("pair_lines: more del unpaired", table.concat(r.del_unpaired, ","), "2,3")
  h.assert_eq("pair_lines: more del add_unpaired", #r.add_unpaired, 0)
end

-- Surplus add lines are left unpaired.
do
  local r = intraline.pair_lines({ "a" }, { "x", "y", "z" })
  h.assert_eq("pair_lines: more add pairs", pairs_to_str(r.pairs), "1-1")
  h.assert_eq("pair_lines: more add del_unpaired", #r.del_unpaired, 0)
  h.assert_eq("pair_lines: more add unpaired", table.concat(r.add_unpaired, ","), "2,3")
end

-- Empty inputs produce no pairs and no unpaired surplus.
do
  local r = intraline.pair_lines({}, {})
  h.assert_eq("pair_lines: empty pairs", #r.pairs, 0)
  h.assert_eq("pair_lines: empty del_unpaired", #r.del_unpaired, 0)
  h.assert_eq("pair_lines: empty add_unpaired", #r.add_unpaired, 0)
end

-- build_pairs couples del/add work items positionally, carrying rows + texts and
-- dropping surplus lines.
do
  local work = intraline.build_pairs(
    { { row = 10, text = "value = 1" }, { row = 12, text = "extra" } },
    { { row = 20, text = "value = 2" } }
  )
  h.assert_eq("build_pairs: count", #work, 1)
  h.assert_eq("build_pairs: del_row", work[1].del_row, 10)
  h.assert_eq("build_pairs: add_row", work[1].add_row, 20)
  h.assert_eq("build_pairs: del_text", work[1].del_text, "value = 1")
  h.assert_eq("build_pairs: add_text", work[1].add_text, "value = 2")
end

-- No add lines means no work items (deletion-only hunk).
do
  local work = intraline.build_pairs({ { row = 1, text = "a" } }, {})
  h.assert_eq("build_pairs: no adds", #work, 0)
end

h.finish()
