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

-- The synthetic shard id under which all content-addressed comments live. It is
-- always loaded (regardless of which commits a review spans) so comments are
-- global per (repo, path, content) rather than tied to a base..target range.
M.COMMENTS_ID = "WORKTREE"

-- Merge a list of inclusive integer ranges into a minimal, sorted, non-adjacent
-- set. Adjacent ranges (e.. e+1) are coalesced.
function M.merge(ranges)
  local sorted = {}
  for _, r in ipairs(ranges) do
    sorted[#sorted + 1] = { r[1], r[2] }
  end
  table.sort(sorted, function(a, b)
    return a[1] < b[1]
  end)
  local out = {}
  for _, r in ipairs(sorted) do
    local last = out[#out]
    if last and r[1] <= last[2] + 1 then
      if r[2] > last[2] then
        last[2] = r[2]
      end
    else
      out[#out + 1] = { r[1], r[2] }
    end
  end
  return out
end

-- Add a range to a set, returning the merged result.
function M.add(ranges, range)
  local copy = {}
  for _, r in ipairs(ranges) do
    copy[#copy + 1] = { r[1], r[2] }
  end
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
      if r[1] < rs then
        out[#out + 1] = { r[1], rs - 1 }
      end
      if r[2] > re then
        out[#out + 1] = { re + 1, r[2] }
      end
    end
  end
  return out
end

-- Does any range in the set contain the single line `lnum`?
function M.covers(ranges, lnum)
  for _, r in ipairs(ranges) do
    if lnum >= r[1] and lnum <= r[2] then
      return true
    end
  end
  return false
end

-- Is the whole inclusive range [s,e] covered by the set? After merging, this is
-- true iff a single range spans it.
function M.range_covered(ranges, range)
  local s, e = range[1], range[2]
  for _, r in ipairs(M.merge(ranges)) do
    if r[1] <= s and e <= r[2] then
      return true
    end
  end
  return false
end

-- ── Content-hash addressing (the floating "worktree" commit) ────────────────
-- Uncommitted changes live on a synthetic commit with no stable line numbers,
-- so its reviewed unit is the **content** of a block of new-file lines rather
-- than a line range. A block is stored as { head, hash, n }: `hash` is
-- sha256 of the joined line texts, `n` the line count, and `head` the exact
-- text of the first line (a cheap anchor used to skip non-matching positions).

-- Build the stored descriptor for a run of new-file line texts.
function M.block_of(lines)
  return {
    head = lines[1],
    hash = vim.fn.sha256(table.concat(lines, "\n")),
    n = #lines,
  }
end

-- Content key for a single comment-anchored line.
function M.line_hash(text)
  return vim.fn.sha256(text)
end

-- Given stored blocks and the current ordered new-file line texts, return the
-- set { [index] = true } of line indices that are "seen". For each block we
-- only consider start positions whose first line equals `head`, then hash the
-- n-line window there — so we hash at most once per occurrence of the head line
-- rather than once per file position.
function M.compute_seen_lines(blocks, line_texts)
  local positions = {}
  for i, t in ipairs(line_texts) do
    positions[t] = positions[t] or {}
    positions[t][#positions[t] + 1] = i
  end
  local n_lines = #line_texts
  local seen = {}
  for _, b in ipairs(blocks) do
    for _, i in ipairs(positions[b.head] or {}) do
      local last = i + b.n - 1
      if last <= n_lines then
        local window = {}
        for j = i, last do
          window[#window + 1] = line_texts[j]
        end
        if vim.fn.sha256(table.concat(window, "\n")) == b.hash then
          for j = i, last do
            seen[j] = true
          end
        end
      end
    end
  end
  return seen
end

-- Pure re-anchoring helper. Given a comment's captured `content` block (a list
-- of line texts), the `anchor` ordinal it was authored against, and the current
-- flattened `diff_texts` sequence, return the start index of the closest
-- consecutive match (all-or-nothing), or nil if the block does not appear.
-- Ties on distance pick the lower index.
function M.resolve(content, anchor, diff_texts)
  local n = #content
  if n == 0 then
    return nil
  end
  local best, best_dist
  for i = 1, #diff_texts - n + 1 do
    local match = true
    for j = 1, n do
      if diff_texts[i + j - 1] ~= content[j] then
        match = false
        break
      end
    end
    if match then
      local dist = math.abs(i - anchor)
      if not best_dist or dist < best_dist then
        best, best_dist = i, dist
      end
    end
  end
  return best
end

-- Split a list of new-file line numbers into maximal contiguous ascending runs.
local function contiguous_runs(lnums)
  local sorted = {}
  for _, l in ipairs(lnums) do
    sorted[#sorted + 1] = l
  end
  table.sort(sorted)
  local runs, cur, prev = {}, nil, nil
  for _, l in ipairs(sorted) do
    if l == prev then
    -- duplicate; skip
    elseif prev and l == prev + 1 then
      cur[#cur + 1] = l
      prev = l
    else
      cur = { l }
      runs[#runs + 1] = cur
      prev = l
    end
  end
  return runs
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
-- Read one shard from disk into `self.data[sha]` (no-op if missing/corrupt).
function Store:read_shard(sha)
  local path = self:shard_path(sha)
  if vim.fn.filereadable(path) ~= 1 then return end
  local content = table.concat(vim.fn.readfile(path), "\n")
  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == "table" then
    decoded.files = decoded.files or {}
    self.data[sha] = decoded
  end
end

function Store:load(shas)
  self.data = {}
  local wanted = {}
  for _, sha in ipairs(shas) do
    wanted[sha] = true
    self:read_shard(sha)
  end
  -- Comments are content-addressed and global; their shard must be present for
  -- every review, even committed-range reviews that don't span it.
  if not wanted[M.COMMENTS_ID] then
    self:read_shard(M.COMMENTS_ID)
  end
  return self.data
end

-- Load a single commit's shard into `self.data` if present and not already
-- loaded (never clobbers in-memory edits). Used to surface comments authored
-- against owner commits outside the reviewed range (e.g. on context lines).
function Store:load_one(sha)
  if self.data[sha] then return end
  local path = self:shard_path(sha)
  if vim.fn.filereadable(path) ~= 1 then return end
  local content = table.concat(vim.fn.readfile(path), "\n")
  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == "table" then
    decoded.files = decoded.files or {}
    self.data[sha] = decoded
  end
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

-- Remove the last comment matching `text` at (commit, path, new_lnum). Used to
-- reverse an add-comment action; no-op if none match.
function Store:remove_comment(sha, path, new_lnum, text)
  local c = self.data[sha]
  local f = c and c.files and c.files[path]
  local list = f and f.comments and f.comments[tostring(new_lnum)]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].text == text then
      table.remove(list, i)
      return
    end
  end
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

-- ── Worktree (content-addressed) store methods ──────────────────────────────
-- The floating commit's slice carries `worktree = true` and a per-file record
-- of { seen = { {head,hash,n}, ... }, comments = { [line_hash] = {{text}} } }.

function Store:wt_commit(id)
  local c = self.data[id]
  if not c then
    c = { worktree = true, files = {} }
    self.data[id] = c
  end
  c.worktree = true
  return c
end

function Store:wt_file(id, path)
  local c = self:wt_commit(id)
  local f = c.files[path]
  if not f then
    f = { seen = {}, comments = {} }
    c.files[path] = f
  end
  return f
end

-- Mark a run of new-file line texts seen (deduped by content hash).
function Store:mark_seen_block(id, path, lines)
  if #lines == 0 then
    return
  end
  local f = self:wt_file(id, path)
  local block = M.block_of(lines)
  for _, b in ipairs(f.seen) do
    if b.hash == block.hash then
      return
    end
  end
  f.seen[#f.seen + 1] = block
end

-- Remove the block whose content matches the given run of line texts.
function Store:unmark_seen_block(id, path, lines)
  if #lines == 0 then
    return
  end
  local f = self:wt_file(id, path)
  local block = M.block_of(lines)
  local out = {}
  for _, b in ipairs(f.seen) do
    if b.hash ~= block.hash then
      out[#out + 1] = b
    end
  end
  f.seen = out
end

-- Stored seen blocks for (worktree, path).
function Store:seen_blocks(id, path)
  local c = self.data[id]
  local f = c and c.files and c.files[path]
  return (f and f.seen) or {}
end

-- Append a comment anchored to a new-file line's content hash.
function Store:wt_add_comment(id, path, line_text, text)
  local f = self:wt_file(id, path)
  local key = M.line_hash(line_text)
  f.comments[key] = f.comments[key] or {}
  f.comments[key][#f.comments[key] + 1] = { text = text }
end

-- Remove the last worktree comment matching `text` at the line's content hash.
function Store:wt_remove_comment(id, path, line_text, text)
  local c = self.data[id]
  local f = c and c.files and c.files[path]
  local list = f and f.comments and f.comments[M.line_hash(line_text)]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].text == text then
      table.remove(list, i)
      return
    end
  end
end

-- Comments anchored to a new-file line's content (by hash).
function Store:wt_comments_for(id, path, line_text)
  local c = self.data[id]
  local f = c and c.files and c.files[path]
  local list = f and f.comments and f.comments[M.line_hash(line_text)]
  return list or {}
end

-- ── Content-addressed comments ──────────────────────────────────────────────
-- All comments live in the always-loaded COMMENTS_ID shard under a top-level
-- `comments` map keyed by path. Each record is { anchor, content = {...}, text }:
-- `content` is the captured line text(s) (one entry per commented line),
-- `anchor` the authoring line (a tiebreak / outdated fallback), `text` the body.
-- Comments are re-anchored by content at render time, independent of any commit.

function Store:comments_commit()
  local c = self.data[M.COMMENTS_ID]
  if not c then
    c = { worktree = true, files = {} }
    self.data[M.COMMENTS_ID] = c
  end
  c.comments = c.comments or {}
  return c
end

-- Append a comment record { anchor, content = {...}, text } for `path`.
function Store:add_comment_record(path, record)
  local c = self:comments_commit()
  c.comments[path] = c.comments[path] or {}
  local list = c.comments[path]
  list[#list + 1] = { anchor = record.anchor, content = record.content, text = record.text }
end

local function content_eq(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- Remove the last comment for `path` matching the given record by anchor,
-- content[] and text. Used to reverse an add; no-op if none match.
function Store:remove_comment_record(path, record)
  local c = self.data[M.COMMENTS_ID]
  local list = c and c.comments and c.comments[path]
  if not list then return end
  for i = #list, 1, -1 do
    local r = list[i]
    if r.anchor == record.anchor and r.text == record.text and content_eq(r.content, record.content) then
      table.remove(list, i)
      return
    end
  end
end

-- All comment records for `path` (possibly empty).
function Store:comments_for(path)
  local c = self.data[M.COMMENTS_ID]
  return (c and c.comments and c.comments[path]) or {}
end

-- ── Addressing adapters ─────────────────────────────────────────────────────
-- Both adapters expose the same operations over **new-file line numbers**, so
-- the higher-level render/mark/comment flows stay identical. The range adapter
-- (real commits) delegates to the line-range helpers; the hash adapter
-- (floating commit) translates line numbers ↔ content via the supplied ordered
-- new-file line texts (`lines[new_lnum] = text`).

function M.range_adapter(store, sha, path)
  return {
    worktree = false,
    is_seen = function(lnum)
      return M.covers(store:seen_ranges(sha, path), lnum)
    end,
    mark = function(lnums)
      for _, run in ipairs(contiguous_runs(lnums)) do
        store:mark_seen(sha, path, { run[1], run[#run] })
      end
    end,
    unmark = function(lnums)
      for _, run in ipairs(contiguous_runs(lnums)) do
        store:unmark_seen(sha, path, { run[1], run[#run] })
      end
    end,
    range_covered = function(s, e)
      return M.range_covered(store:seen_ranges(sha, path), { s, e })
    end,
    add_comment = function(lnum, text)
      store:add_comment(sha, path, lnum, text)
    end,
    remove_comment = function(lnum, text)
      store:remove_comment(sha, path, lnum, text)
    end,
    comments_at = function(lnum)
      return store:comments_at(sha, path, lnum)
    end,
  }
end

function M.hash_adapter(store, id, path, lines)
  local function seen_set()
    return M.compute_seen_lines(store:seen_blocks(id, path), lines)
  end
  local function texts_of(run)
    local t = {}
    for _, l in ipairs(run) do
      t[#t + 1] = lines[l]
    end
    return t
  end
  return {
    worktree = true,
    is_seen = function(lnum)
      return seen_set()[lnum] == true
    end,
    mark = function(lnums)
      for _, run in ipairs(contiguous_runs(lnums)) do
        store:mark_seen_block(id, path, texts_of(run))
      end
    end,
    unmark = function(lnums)
      for _, run in ipairs(contiguous_runs(lnums)) do
        store:unmark_seen_block(id, path, texts_of(run))
      end
    end,
    range_covered = function(s, e)
      local seen = seen_set()
      for l = s, e do
        if not seen[l] then
          return false
        end
      end
      return true
    end,
    add_comment = function(lnum, text)
      store:wt_add_comment(id, path, lines[lnum], text)
    end,
    remove_comment = function(lnum, text)
      store:wt_remove_comment(id, path, lines[lnum], text)
    end,
    comments_at = function(lnum)
      return store:wt_comments_for(id, path, lines[lnum])
    end,
  }
end

return M
