-- glean.intraline: pure helpers for intra-line (word-level) diff highlighting.
--
-- This module is deliberately free of any nvim API so it can be unit-tested
-- headless like glean.diff. Stage 1 provides only the tokenizer; alignment and
-- line pairing land in later stages.
local M = {}

-- A token: { text = <string>, col = <0-based byte offset>, len = <byte len> }.
--
-- Tokenization rule: a maximal run of [A-Za-z0-9_] is a single token; every
-- other byte is its own single-byte token. `col` is the 0-based byte offset of
-- the token within `s` (callers add the marker prefix offset themselves).
local function is_word_byte(b)
  return (b >= 48 and b <= 57) -- 0-9
    or (b >= 65 and b <= 90) -- A-Z
    or (b >= 97 and b <= 122) -- a-z
    or b == 95 -- _
end

function M.tokenize(s)
  local tokens = {}
  local i = 1
  local n = #s
  while i <= n do
    local b = s:byte(i)
    if is_word_byte(b) then
      local start = i
      i = i + 1
      while i <= n and is_word_byte(s:byte(i)) do
        i = i + 1
      end
      tokens[#tokens + 1] = { text = s:sub(start, i - 1), col = start - 1, len = i - start }
    else
      tokens[#tokens + 1] = { text = s:sub(i, i), col = i - 1, len = 1 }
      i = i + 1
    end
  end
  return tokens
end

return M
