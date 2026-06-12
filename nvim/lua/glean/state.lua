-- glean.state: the persisted ReviewStore — the single source of truth for what
-- the user has reviewed. It is keyed by **commit sha** (not branch), so a mark
-- left on a commit reappears in any branch/clone that contains that commit. On
-- disk it is sharded one JSON file per commit (`<dir>/<sha>.json`); in memory
-- it is the merged map { [sha] = { files = { [path] = { seen, comments } } } }.
--
-- The atomic addressable unit is a **new-file line range within a commit**
-- (`{start, end}`, in that commit's immutable post-image), so the range-math
-- helpers below (pure functions over literal range tables) are the heart of the
-- module and are exercised directly by the Tier-1 tests.
local M = {}

-- Merge a list of inclusive integer ranges into a minimal, sorted, non-adjacent
-- set. Adjacent ranges (e.. e+1) are coalesced.
function M.merge(ranges)
  local sorted = {}
  for _, r in ipairs(ranges) do sorted[#sorted + 1] = { r[1], r[2] } end
  table.sort(sorted, function(a, b) return a[1] < b[1] end)
  local out = {}
  for _, r in ipairs(sorted) do
    local last = out[#out]
    if last and r[1] <= last[2] + 1 then
      if r[2] > last[2] then last[2] = r[2] end
    else
      out[#out + 1] = { r[1], r[2] }
    end
  end
  return out
end

-- Add a range to a set, returning the merged result.
function M.add(ranges, range)
  local copy = {}
  for _, r in ipairs(ranges) do copy[#copy + 1] = { r[1], r[2] } end
  copy[#copy + 1] = { range[1], range[2] }
  return M.merge(copy)
end

-- Subtract a range from a set, returning the merged remainder.
function M.remove(ranges, range)
  local rs, re = range[1], range[2]
  local out = {}
  for _, r in ipairs(M.merge(ranges)) do
    if re < r[1] or rs > r[2] then
      out[#out + 1] = { r[1], r[2] }
    else
      if r[1] < rs then out[#out + 1] = { r[1], rs - 1 } end
      if r[2] > re then out[#out + 1] = { re + 1, r[2] } end
    end
  end
  return out
end

-- Does any range in the set contain the single line `lnum`?
function M.covers(ranges, lnum)
  for _, r in ipairs(ranges) do
    if lnum >= r[1] and lnum <= r[2] then return true end
  end
  return false
end

-- Is the whole inclusive range [s,e] covered by the set? After merging, this is
-- true iff a single range spans it.
function M.range_covered(ranges, range)
  local s, e = range[1], range[2]
  for _, r in ipairs(M.merge(ranges)) do
    if r[1] <= s and e <= r[2] then return true end
  end
  return false
end

local Store = {}
Store.__index = Store

-- Create a store. `opts.dir` (injectable for tests) defaults to
-- stdpath("data")/glean. Data is empty until :load.
function M.new(opts)
  opts = opts or {}
  local dir = opts.dir or (vim.fn.stdpath("data") .. "/glean")
  return setmetatable({ dir = dir, data = {} }, Store)
end

function Store:shard_path(sha)
  return self.dir .. "/" .. sha .. ".json"
end

-- Read the shards for the given commit shas into `self.data`, replacing any
-- prior contents. Missing/unreadable/corrupt shards are silently skipped (a
-- never-reviewed commit simply has no entry). Returns self.data.
function Store:load(shas)
  self.data = {}
  for _, sha in ipairs(shas) do
    local path = self:shard_path(sha)
    if vim.fn.filereadable(path) == 1 then
      local content = table.concat(vim.fn.readfile(path), "\n")
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == "table" then
        decoded.files = decoded.files or {}
        self.data[sha] = decoded
      end
    end
  end
  return self.data
end

-- Get (creating if absent) the in-memory slice for a commit.
function Store:commit(sha)
  local c = self.data[sha]
  if not c then
    c = { files = {} }
    self.data[sha] = c
  end
  return c
end

-- Get (creating if absent) the per-file record for a (commit, path).
function Store:file(sha, path)
  local c = self:commit(sha)
  local f = c.files[path]
  if not f then
    f = { seen = {}, comments = {} }
    c.files[path] = f
  end
  return f
end

-- Mark a new-file line range seen for (commit, path).
function Store:mark_seen(sha, path, range)
  local f = self:file(sha, path)
  f.seen = M.add(f.seen, range)
end

-- Unmark (remove) a new-file line range from (commit, path).
function Store:unmark_seen(sha, path, range)
  local f = self:file(sha, path)
  f.seen = M.remove(f.seen, range)
end

-- Seen ranges for (commit, path) (possibly empty).
function Store:seen_ranges(sha, path)
  local c = self.data[sha]
  local f = c and c.files and c.files[path]
  return (f and f.seen) or {}
end

-- Append a comment to (commit, path) at a new-file line number. Comments are
-- stored keyed by the **string** form of new_lnum so they round-trip through
-- JSON (object keys are always strings); each line holds a list of texts.
function Store:add_comment(sha, path, new_lnum, text)
  local f = self:file(sha, path)
  local key = tostring(new_lnum)
  f.comments[key] = f.comments[key] or {}
  f.comments[key][#f.comments[key] + 1] = { text = text }
end

-- List of comment texts for (commit, path) at a new-file line number.
function Store:comments_at(sha, path, new_lnum)
  local c = self.data[sha]
  local f = c and c.files and c.files[path]
  local list = f and f.comments and f.comments[tostring(new_lnum)]
  return list or {}
end

-- Persist a single commit's shard (the unit a mark/comment edit rewrites).
function Store:save_commit(sha)
  vim.fn.mkdir(self.dir, "p")
  local slice = self.data[sha] or { files = {} }
  vim.fn.writefile({ vim.json.encode(slice) }, self:shard_path(sha))
end

return M
