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

h.finish()
