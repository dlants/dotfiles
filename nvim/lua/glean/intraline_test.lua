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

-- Similar lines pair up; the matching runs in order with no surplus.
do
  local r = intraline.pair_lines(
    { "value = 1", "name = foo", "flag = true" },
    { "value = 2", "name = bar", "flag = false" }
  )
  h.assert_eq("pair_lines: similar pairs", pairs_to_str(r.pairs), "1-1|2-2|3-3")
  h.assert_eq("pair_lines: similar del_unpaired", #r.del_unpaired, 0)
  h.assert_eq("pair_lines: similar add_unpaired", #r.add_unpaired, 0)
end

-- A lone changed line buried among unrelated insertions pairs with its true
-- match, not positionally with the first add; the unrelated adds stay unpaired.
do
  local r = intraline.pair_lines(
    { "total = count + 1" },
    { "import os", "total = count + 2", "return None" }
  )
  h.assert_eq("pair_lines: buried pairs", pairs_to_str(r.pairs), "1-2")
  h.assert_eq("pair_lines: buried del_unpaired", #r.del_unpaired, 0)
  h.assert_eq("pair_lines: buried add_unpaired", table.concat(r.add_unpaired, ","), "1,3")
end

-- Order is preserved: pairings never cross even when a later del is most similar
-- to an earlier add.
do
  local r = intraline.pair_lines(
    { "alpha = 1", "beta = 2" },
    { "beta = 3", "alpha = 4" }
  )
  -- 1-2 (alpha) and 2-1 (beta) would cross, so only the better single pair wins.
  h.assert_true("pair_lines: order no crossing", #r.pairs <= 1)
end

-- Dissimilar runs leave everything unpaired.
do
  local r = intraline.pair_lines({ "import os" }, { "return None" })
  h.assert_eq("pair_lines: dissimilar pairs", #r.pairs, 0)
  h.assert_eq("pair_lines: dissimilar del_unpaired", table.concat(r.del_unpaired, ","), "1")
  h.assert_eq("pair_lines: dissimilar add_unpaired", table.concat(r.add_unpaired, ","), "1")
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

-- is_current gates async refinement chunks: valid buffer + matching generation.
do
  h.assert_eq("is_current: valid + match", intraline.is_current(3, 3, true), true)
  h.assert_eq("is_current: stale gen", intraline.is_current(2, 3, true), false)
  h.assert_eq("is_current: invalid buffer", intraline.is_current(3, 3, false), false)
end

-- Regression: a single changed line in a hunk full of pure insertions must pair
-- with its *matching* add line, not positionally with the first add. Here one
-- del (`      emit(marker .. dl.text,`) becomes `      local row = emit(...)`,
-- surrounded by brand-new lines. Positional pairing wrongly couples it with the
-- first add (`    local dels, adds = {}, {}`); correct pairing finds the
-- `local row = emit` line and emphasizes just the inserted `local row = `.
do
  local dels = {
    { row = 4, text = "      emit(marker .. dl.text," },
  }
  local adds = {
    { row = 3, text = "    local dels, adds = {}, {}" },
    { row = 6, text = "      local row = emit(marker .. dl.text," },
    { row = 7, text = '      if dl.kind == "del" then' },
    { row = 8, text = "        dels[#dels + 1] = { row = row, text = dl.text }" },
    { row = 9, text = '      elseif dl.kind == "add" then' },
    { row = 10, text = "        adds[#adds + 1] = { row = row, text = dl.text }" },
    { row = 13, text = "    for _, w in ipairs(intraline.build_pairs(dels, adds)) do" },
    { row = 14, text = "      intra_work[#intra_work + 1] = w" },
  }
  local work = intraline.build_pairs(dels, adds)
  h.assert_eq("hunk: one work item", #work, 1)
  h.assert_eq(
    "hunk: pairs with matching add",
    work[1].add_text,
    "      local row = emit(marker .. dl.text,"
  )
  local r = intraline.align(work[1].del_text, work[1].add_text)
  h.assert_true("hunk: align non-nil", r ~= nil)
  h.assert_eq("hunk: del emphasis empty", segs_to_str(r.a_segs), "")
  h.assert_eq("hunk: add emphasis is the insertion", segs_to_str(r.b_segs), "5:17")
end

h.finish()
