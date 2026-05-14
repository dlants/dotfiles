-- Fuzzy match scoring for needle.
--
-- DP-based fzf-inspired matcher with affine gap penalties. Returns
-- (score, positions) for a needle/haystack pair, or nil if there is no match.
-- The DP buffers are reused across calls to avoid GC pressure on the hot path.

local M = {}

local BSLASH, BDASH, BUNDER, BDOT, BSPACE = 47, 45, 95, 46, 32
local BUA, BUZ, BLA, BLZ = 65, 90, 97, 122

-- Scoring constants (fzf-inspired). Scaled to be comparable with the per-file
-- signal weights (in_buffer, recent_access, ...) used by the ranker, and tuned
-- to bias toward contiguous matches near the end of the path.
local SCORE_MATCH     = 16
local BONUS_BOUNDARY  = 8     -- after _ - . or space
local BONUS_SLASH     = 12    -- after / -- stronger than other word boundaries
local BONUS_CAMEL     = 8     -- lower -> upper transition
local BONUS_FIRST_POS = 8     -- first byte of the haystack
local FIRST_CHAR_MULT = 2     -- bonus multiplier for needle's first matched char
local CASE_BONUS      = 4     -- exact case match
local GAP_OPEN        = 3     -- one-time cost when introducing a gap
local GAP_EXT         = 1     -- per-char gap extension cost
local FILENAME_BONUS  = 4     -- small tiebreaker for matches inside the filename

-- Per-position structural bonus. Higher means the position is a more
-- "natural" start-of-word in the haystack.
local function bonus_at(haystack, idx)
  if idx == 1 then return BONUS_FIRST_POS end
  local prev = haystack:byte(idx - 1)
  local cur  = haystack:byte(idx)
  if prev == BSLASH then return BONUS_SLASH end
  if prev == BUNDER or prev == BDASH or prev == BDOT or prev == BSPACE then return BONUS_BOUNDARY end
  if cur >= BUA and cur <= BUZ and prev >= BLA and prev <= BLZ then return BONUS_CAMEL end
  return 0
end

local function find_last_slash(s)
  for i = #s, 1, -1 do
    if s:byte(i) == BSLASH then return i end
  end
  return 0
end

local NEG_INF = -math.huge
local D_buf, G_buf = {}, {}

-- DP-based fuzzy match with affine gap penalties. Returns (score, positions)
-- or nil if no match.
--
-- State (1-indexed; D[0][_] / G[0][_] are base cases):
--   D[i][j] = best score where needle[i] is matched at haystack[j]
--   G[i][j] = max over j' <= j of ( D[i][j'] - GAP_EXT * (j - j') )
--             i.e. best D[i][.] so far, decayed by GAP_EXT per intervening char
--
-- For each (i, j) where needle_lower[i] == haystack_lower[j]:
--   D[i][j] = match_score + max(
--               D[i-1][j-1],                          -- consecutive (no gap)
--               G[i-1][j-2] - GAP_OPEN - GAP_EXT      -- gap of length >= 1
--             )
--   where match_score = SCORE_MATCH + bonus*first_mult + case_bonus
-- Otherwise D[i][j] = -inf.
-- G[i][j] = max( G[i][j-1] - GAP_EXT, D[i][j] ).
function M.score_match(needle, needle_lower, haystack, haystack_lower)
  local n = #needle
  local h = #haystack
  if n == 0 then return 0, nil end
  if n > h then return nil end

  -- Cheap pre-filter: needle must be a subsequence of haystack.
  do
    local idx = 1
    for i = 1, n do
      local nc = needle_lower:byte(i)
      while idx <= h and haystack_lower:byte(idx) ~= nc do
        idx = idx + 1
      end
      if idx > h then return nil end
      idx = idx + 1
    end
  end

  -- Ensure DP rows exist. Base row (i=0) represents the empty-needle prefix:
  -- D[0][j] = 0 so the "consecutive" branch from i=0 to i=1 produces just
  -- match_score (no gap penalty). G[0][_] is left at NEG_INF so the gap branch
  -- never wins for the first needle character.
  for i = 0, n do
    D_buf[i] = D_buf[i] or {}
    G_buf[i] = G_buf[i] or {}
  end
  local D0, G0 = D_buf[0], G_buf[0]
  for j = 0, h do
    D0[j] = 0
    G0[j] = NEG_INF
  end

  for i = 1, n do
    local D_i, G_i       = D_buf[i],   G_buf[i]
    local D_prev, G_prev = D_buf[i-1], G_buf[i-1]
    D_i[0] = NEG_INF
    G_i[0] = NEG_INF
    local nc  = needle_lower:byte(i)
    local ncc = needle:byte(i)
    local first_mult = (i == 1) and FIRST_CHAR_MULT or 1
    for j = 1, h do
      local d = NEG_INF
      if haystack_lower:byte(j) == nc then
        local b = bonus_at(haystack, j) * first_mult
        local case_bonus = (ncc == haystack:byte(j)) and CASE_BONUS or 0
        local match_score = SCORE_MATCH + b + case_bonus
        local consec = D_prev[j-1] + match_score
        local gap = NEG_INF
        if j >= 2 then
          gap = G_prev[j-2] + match_score - GAP_OPEN - GAP_EXT
        end
        d = (consec > gap) and consec or gap
      end
      D_i[j] = d
      local g_left = G_i[j-1] - GAP_EXT
      G_i[j] = (d > g_left) and d or g_left
    end
  end

  -- Best ending column for needle[n]. j must be >= n to fit n needle chars.
  local D_n = D_buf[n]
  local end_j, best = 0, NEG_INF
  for j = n, h do
    local d = D_n[j]
    if d > best then best = d; end_j = j end
  end
  if end_j == 0 or best == NEG_INF then return nil end

  -- Traceback. At each step decide whether D[i][j] came from the consecutive
  -- branch (D[i-1][j-1] + match_score) or the gap branch (G[i-1][j-2] + ...).
  -- For the gap branch we recover the actual previous position by scanning
  -- backward from j-2 for the k that realized G[i-1][j-2].
  local positions = {}
  positions[n] = end_j
  local j = end_j
  for i = n, 2, -1 do
    local D_prev = D_buf[i-1]
    local b = bonus_at(haystack, j)   -- i > 1, no first_mult here
    local case_bonus = (needle:byte(i) == haystack:byte(j)) and CASE_BONUS or 0
    local match_score = SCORE_MATCH + b + case_bonus
    local consec = D_prev[j-1] + match_score
    if D_buf[i][j] == consec then
      j = j - 1
    else
      -- Find largest k <= j-2 such that D_prev[k] - GAP_EXT * (j - 2 - k)
      -- equals G_buf[i-1][j-2] (i.e. the k that realized the running max).
      local target = G_buf[i-1][j-2]
      local k = j - 2
      while k >= 1 and (D_prev[k] - GAP_EXT * (j - 2 - k)) ~= target do
        k = k - 1
      end
      j = k
    end
    positions[i-1] = j
  end

  -- Post-DP tiebreaker: small extra bonus when the whole match sits inside
  -- the filename portion of the path. Span is already handled by the affine
  -- gap penalties baked into the DP, so no span penalty here.
  local total = best
  local last_slash = find_last_slash(haystack)
  if positions[1] > last_slash then total = total + FILENAME_BONUS end
  return total, positions
end

-- Convenience: take a needle and a list of haystacks, return matches sorted by
-- descending score. Useful for tests and for callers that don't manage their
-- own lowercase caches.
function M.rank(needle, haystacks)
  local needle_lower = needle:lower()
  local results = {}
  for _, h in ipairs(haystacks) do
    local score, positions = M.score_match(needle, needle_lower, h, h:lower())
    if score then
      results[#results + 1] = { text = h, score = score, positions = positions }
    end
  end
  table.sort(results, function(a, b) return a.score > b.score end)
  return results
end

return M
