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

-- Affine-gap (Gotoh) token alignment cost constants. GAP_OPEN > GAP_EXTEND so a
-- contiguous run of changed tokens is cheaper than the same number scattered,
-- which keeps highlight segments blocky. Unequal tokens never align on the
-- diagonal (LCS-style: only equal tokens match); a substitution is therefore
-- modeled as a gap on each side.
local GAP_OPEN = 3
local GAP_EXTEND = 1
-- Early-termination / "too different" threshold, scaled by the longer token
-- sequence. If the cheapest alignment cost exceeds this, the pair is abandoned.
local COST_FACTOR = 2
local INF = math.huge

-- Merge a sorted list of changed token indices into byte-range segments
-- { start_col, end_col } (end_col exclusive). Consecutive token indices are
-- byte-adjacent (tokenization covers every byte), so they coalesce.
local function merge_segments(tokens, changed)
  local segs = {}
  local i = 1
  while i <= #changed do
    local j = i
    while j < #changed and changed[j + 1] == changed[j] + 1 do
      j = j + 1
    end
    local first = tokens[changed[i]]
    local last = tokens[changed[j]]
    segs[#segs + 1] = { start_col = first.col, end_col = last.col + last.len }
    i = j + 1
  end
  return segs
end

-- align(a, b) aligns the token sequences of two raw line strings with an
-- affine-gap DP. Returns { a_segs, b_segs } (byte-range segments of changed
-- tokens on each side) for sufficiently similar lines, or nil when the lines are
-- too different (early termination). Identical lines yield empty segment lists.
function M.align(a, b)
  local ta = M.tokenize(a)
  local tb = M.tokenize(b)
  local m = #ta
  local n = #tb
  local max_cost = math.max(m, n) * COST_FACTOR

  -- Three cost matrices (Gotoh): Mm = last step aligned a token to b token;
  -- Ga = gap in a (a token from b consumed); Gb = gap in b (a token from a
  -- consumed). Rows 0..m, cols 0..n.
  local Mm, Ga, Gb = {}, {}, {}
  for i = 0, m do
    Mm[i], Ga[i], Gb[i] = {}, {}, {}
  end
  Mm[0][0], Ga[0][0], Gb[0][0] = 0, INF, INF
  for j = 1, n do
    Mm[0][j] = INF
    Ga[0][j] = GAP_OPEN + (j - 1) * GAP_EXTEND
    Gb[0][j] = INF
  end
  for i = 1, m do
    Mm[i][0] = INF
    Ga[i][0] = INF
    Gb[i][0] = GAP_OPEN + (i - 1) * GAP_EXTEND
  end

  for i = 1, m do
    local row_min = INF
    for j = 1, n do
      if ta[i].text == tb[j].text then
        Mm[i][j] = math.min(Mm[i - 1][j - 1], Ga[i - 1][j - 1], Gb[i - 1][j - 1])
      else
        Mm[i][j] = INF
      end
      Ga[i][j] = math.min(math.min(Mm[i][j - 1], Gb[i][j - 1]) + GAP_OPEN, Ga[i][j - 1] + GAP_EXTEND)
      Gb[i][j] = math.min(math.min(Mm[i - 1][j], Ga[i - 1][j]) + GAP_OPEN, Gb[i - 1][j] + GAP_EXTEND)
      row_min = math.min(row_min, Mm[i][j], Ga[i][j], Gb[i][j])
    end
    -- Early termination: no cell in this frontier is cheap enough to recover.
    if m > 0 and n > 0 and row_min > max_cost then
      return nil
    end
  end

  local final = math.min(Mm[m][n], Ga[m][n], Gb[m][n])
  if final == INF or final > max_cost then
    return nil
  end

  -- Backtrace, collecting changed token indices on each side.
  local a_changed, b_changed = {}, {}
  local i, j = m, n
  local state -- "M" | "Ga" | "Gb"
  if Mm[m][n] <= Ga[m][n] and Mm[m][n] <= Gb[m][n] then
    state = "M"
  elseif Ga[m][n] <= Gb[m][n] then
    state = "Ga"
  else
    state = "Gb"
  end
  while i > 0 or j > 0 do
    if state == "M" then
      local prev = Mm[i][j]
      i, j = i - 1, j - 1
      if Mm[i][j] == prev then
        state = "M"
      elseif Ga[i][j] == prev then
        state = "Ga"
      else
        state = "Gb"
      end
    elseif state == "Ga" then
      b_changed[#b_changed + 1] = j
      if Ga[i][j - 1] + GAP_EXTEND == Ga[i][j] then
        state = "Ga"
      elseif Mm[i][j - 1] + GAP_OPEN == Ga[i][j] then
        state = "M"
      else
        state = "Gb"
      end
      j = j - 1
    else -- "Gb"
      a_changed[#a_changed + 1] = i
      if Gb[i - 1][j] + GAP_EXTEND == Gb[i][j] then
        state = "Gb"
      elseif Mm[i - 1][j] + GAP_OPEN == Gb[i][j] then
        state = "M"
      else
        state = "Ga"
      end
      i = i - 1
    end
  end

  -- Backtrace collected indices in descending order; reverse for merge.
  local function reverse(t)
    local r = {}
    for k = #t, 1, -1 do
      r[#r + 1] = t[k]
    end
    return r
  end

  return {
    a_segs = merge_segments(ta, reverse(a_changed)),
    b_segs = merge_segments(tb, reverse(b_changed)),
  }
end

-- similarity(a, b) scores how alike two lines are, in [0, 1], or nil when they
-- are too different to align at all (M.align early-terminates). The score is the
-- fraction of bytes left unchanged by the token alignment: identical lines score
-- 1, and the more bytes the alignment marks as changed, the lower the score.
-- Normalizing by both lines' length keeps long and short lines comparable.
local function similarity(a, b)
  local r = M.align(a, b)
  if r == nil then
    return nil
  end
  local changed = 0
  for _, s in ipairs(r.a_segs) do
    changed = changed + (s.end_col - s.start_col)
  end
  for _, s in ipairs(r.b_segs) do
    changed = changed + (s.end_col - s.start_col)
  end
  local total = #a + #b
  if total == 0 then
    return 1
  end
  return 1 - changed / total
end

-- A pair is kept only when its similarity beats this threshold; below it, the
-- two lines read as independent (full rewrite) and stay unpaired.
local PAIR_THRESHOLD = 0.5

-- pair_lines couples a hunk's deleted lines with its added lines by similarity,
-- order-preserving (a Needleman-Wunsch alignment one level up, with whole lines
-- as the elements). Every (del, add) cell is scored with `similarity`; the outer
-- DP then picks a non-crossing set of pairs that maximizes total similarity.
-- Each matched pair contributes `sim - PAIR_THRESHOLD` (so a pair is only worth
-- taking when its similarity clears the threshold) and gaps (an unpaired del or
-- add) contribute nothing. Returns
-- { pairs = { { di, ai }, ... }, del_unpaired = { di, ... },
--   add_unpaired = { ai, ... } } with 1-based indices into the input lists.
--
-- The inner per-pair token alignment (M.align) is re-run by the caller on each
-- returned pair to obtain the changed-token segments.
function M.pair_lines(del_texts, add_texts)
  local m = #del_texts
  local n = #add_texts

  -- sim[i][j] is the normalized similarity of del i and add j, or nil when too
  -- different to ever pair.
  local sim = {}
  for i = 1, m do
    sim[i] = {}
    for j = 1, n do
      sim[i][j] = similarity(del_texts[i], add_texts[j])
    end
  end

  -- dp[i][j] = best achievable score aligning del 1..i against add 1..j. Gaps
  -- add 0; a diagonal step pairs del i with add j for `sim - PAIR_THRESHOLD`,
  -- which is only positive (and so only chosen) when the pair clears threshold.
  local dp = {}
  for i = 0, m do
    dp[i] = {}
    dp[i][0] = 0
  end
  for j = 0, n do
    dp[0][j] = 0
  end
  for i = 1, m do
    for j = 1, n do
      local best = math.max(dp[i - 1][j], dp[i][j - 1])
      local s = sim[i][j]
      if s ~= nil then
        local diag = dp[i - 1][j - 1] + (s - PAIR_THRESHOLD)
        if diag > best then
          best = diag
        end
      end
      dp[i][j] = best
    end
  end

  -- Backtrace: prefer a diagonal pairing only when it actually produced the
  -- cell's score (and cleared threshold), otherwise step through the gap.
  local pairs_rev = {}
  local del_paired, add_paired = {}, {}
  local i, j = m, n
  while i > 0 and j > 0 do
    local s = sim[i][j]
    if s ~= nil and (s - PAIR_THRESHOLD) >= 0 and dp[i][j] == dp[i - 1][j - 1] + (s - PAIR_THRESHOLD) then
      pairs_rev[#pairs_rev + 1] = { i, j }
      del_paired[i] = true
      add_paired[j] = true
      i, j = i - 1, j - 1
    elseif dp[i - 1][j] >= dp[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  local pairs_out = {}
  for k = #pairs_rev, 1, -1 do
    pairs_out[#pairs_out + 1] = pairs_rev[k]
  end
  local del_unpaired, add_unpaired = {}, {}
  for di = 1, m do
    if not del_paired[di] then
      del_unpaired[#del_unpaired + 1] = di
    end
  end
  for ai = 1, n do
    if not add_paired[ai] then
      add_unpaired[#add_unpaired + 1] = ai
    end
  end
  return { pairs = pairs_out, del_unpaired = del_unpaired, add_unpaired = add_unpaired }
end

-- build_pairs couples a hunk's del/add lines into a flat work-list ready for the
-- renderer. `dels`/`adds` are lists of { row, text } (buffer row + raw line text,
-- marker prefix excluded). Pairing is the order-preserving similarity coupling of
-- M.pair_lines; each returned item is
-- { del_row, add_row, del_text, add_text }. Unpaired surplus lines yield no item
-- (their phase-1 full-line highlight stands).
function M.build_pairs(dels, adds)
  local del_texts, add_texts = {}, {}
  for _, d in ipairs(dels) do
    del_texts[#del_texts + 1] = d.text
  end
  for _, a in ipairs(adds) do
    add_texts[#add_texts + 1] = a.text
  end
  local paired = M.pair_lines(del_texts, add_texts)
  local work = {}
  for _, p in ipairs(paired.pairs) do
    local d, a = dels[p[1]], adds[p[2]]
    work[#work + 1] = { del_row = d.row, add_row = a.row, del_text = d.text, add_text = a.text }
  end
  return work
end

-- is_current decides whether an in-flight async refinement chunk may still run:
-- the buffer must remain valid and the generation captured when the chunk was
-- scheduled must still match the session's current generation. A re-render or
-- reload bumps the generation, so any stale chunk cleanly abandons its work.
function M.is_current(gen, current_gen, buf_valid)
  return buf_valid and gen == current_gen
end

return M
