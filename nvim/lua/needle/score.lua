-- Fuzzy match scoring for needle.
--
-- DP-based fzy-style matcher. Returns (score, positions) for a needle/haystack
-- pair, or nil if there is no match. The DP buffers are reused across calls to
-- avoid GC pressure on the hot path.

local M = {}

local BSLASH, BDASH, BUNDER, BDOT, BSPACE = 47, 45, 95, 46, 32
local BUA, BUZ, BLA, BLZ = 65, 90, 97, 122

-- Per-position structural bonus. Higher means the position is a more
-- "natural" start-of-word in the haystack.
local function bonus_at(haystack, idx)
  if idx == 1 then return 3 end
  local prev = haystack:byte(idx - 1)
  local cur  = haystack:byte(idx)
  if prev == BSLASH then return 5 end
  if prev == BUNDER or prev == BDASH or prev == BDOT or prev == BSPACE then return 2 end
  if cur >= BUA and cur <= BUZ and prev >= BLA and prev <= BLZ then return 2 end
  return 0
end

local function find_last_slash(s)
  for i = #s, 1, -1 do
    if s:byte(i) == BSLASH then return i end
  end
  return 0
end

local NEG_INF = -math.huge
local D_buf, M_buf = {}, {}

-- DP-based fuzzy match. Returns (score, positions) or nil if no match.
--
-- Recurrence (1-indexed; D[0][_] / M[0][_] are base cases):
--   D[i][j] = best score where needle[i] is matched at haystack[j]
--   M[i][j] = max over j' <= j of D[i][j']  (best with needle[1..i] in haystack[1..j])
--
-- For each (i, j) where needle_lower[i] == haystack_lower[j]:
--   D[i][j] = max( M[i-1][j-1] + 1 + bonus(j) + case_bonus,        -- non-consecutive
--                  D[i-1][j-1] + 1 + bonus(j) + 2 + case_bonus )   -- consecutive (+2)
--   M[i][j] = max( M[i][j-1], D[i][j] )
--
-- Otherwise D[i][j] = -inf and M[i][j] = M[i][j-1].
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

  -- Ensure DP rows exist; row 0 is the base case (empty-needle prefix).
  for i = 0, n do
    D_buf[i] = D_buf[i] or {}
    M_buf[i] = M_buf[i] or {}
  end
  local D0, M0 = D_buf[0], M_buf[0]
  for j = 0, h do
    M0[j] = 0
    D0[j] = NEG_INF
  end

  for i = 1, n do
    local D_i, M_i     = D_buf[i],   M_buf[i]
    local D_prev, M_prev = D_buf[i-1], M_buf[i-1]
    M_i[0] = NEG_INF
    D_i[0] = NEG_INF
    local nc  = needle_lower:byte(i)
    local ncc = needle:byte(i)
    for j = 1, h do
      local d = NEG_INF
      if haystack_lower:byte(j) == nc then
        local b = bonus_at(haystack, j)
        local case_bonus = (ncc == haystack:byte(j)) and 0.5 or 0
        local from_m = M_prev[j-1] + 1 + b + case_bonus
        -- consecutive match: +2 in addition to the +1 base.
        local from_d = D_prev[j-1] + 3 + b + case_bonus
        d = (from_m > from_d) and from_m or from_d
      end
      D_i[j] = d
      local m_left = M_i[j-1]
      M_i[j] = (d > m_left) and d or m_left
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
  -- branch (D[i-1][j-1]) or the non-consecutive branch (M[i-1][j-1]).
  local positions = {}
  positions[n] = end_j
  local j = end_j
  for i = n, 2, -1 do
    local D_prev = D_buf[i-1]
    local M_prev = M_buf[i-1]
    local b = bonus_at(haystack, j)
    local case_bonus = (needle:byte(i) == haystack:byte(j)) and 0.5 or 0
    local from_d = D_prev[j-1] + 3 + b + case_bonus
    if D_buf[i][j] == from_d then
      j = j - 1
    else
      -- Find the latest j' < j with D[i-1][j'] == M[i-1][j-1].
      local target = M_prev[j-1]
      local k = j - 1
      while k >= 1 and D_prev[k] ~= target do
        k = k - 1
      end
      j = k
    end
    positions[i-1] = j
  end

  -- Post-DP bonuses: filename containment + span penalty.
  local total = best
  local last_slash = find_last_slash(haystack)
  if positions[1] > last_slash then total = total + 8 end
  total = total - (positions[n] - positions[1]) * 0.1
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
