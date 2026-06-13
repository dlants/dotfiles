-- glean: review the diff between two git refs in a single foldable buffer.
--
-- The model (FileEntries / Commits from glean.git, overlaid with the persisted
-- ReviewStore from glean.state) is the single source of truth; the buffer is a
-- pure projection of it. A parallel `row_map[row]` resolves any cursor row back
-- to its commit/file/hunk/line so actions can act on the semantic target.
--
-- Two scopes share one review store:
--   - "combined": the net diff base...target (Stage 2; seen overlay is Stage 4).
--   - "commits": every commit laid out flat, the natural place seen marks and
--     comments are *authored* against a stable (commit_sha, path, new_lnum).
--
-- Collapse is ephemeral session view-state: it is initialized from seen status
-- when a scope is (re)built, then evolves independently and is never persisted.
local git_mod = require("glean.git")
local state_mod = require("glean.state")
local provenance = require("glean.provenance")
local M = {}
local api = vim.api

-- Reserved non-sha id for the synthetic "floating" commit that stands in for the
-- working tree on top of HEAD. Its reviewed units are content-addressed (hashes)
-- rather than line ranges, since uncommitted lines have no stable line numbers.
M.WORKTREE = "WORKTREE"
local NS = api.nvim_create_namespace("glean_hl")
local COMMENT_NS = api.nvim_create_namespace("glean_comments")

M.config = {
  default_base = "main",
}

-- Registry of live glean buffers, keyed by (repo_root, base, target), so a
-- second open of the same diff reuses its persistent, listed buffer instead of
-- spawning a duplicate. Lets you jump to a source file and come back via the
-- buffer list / `<C-^>`.
local buffers = {}

-- Live session per buffer key, so a reopen/refresh can stop the previous one's
-- update timer; and content-addressed collapse overrides per buffer key, kept in
-- process memory so a reload-from-disk never loses expand/collapse state.
local sessions = {}
local views = {}

-- How often the live work-tree review polls the repo for changes (ms).
local LIVE_INTERVAL_MS = 1500

local function buffer_key(repo_root, base, target)
  return table.concat({ repo_root, base, target }, "\0")
end

-- Resolve the repo root from the buffer Glean was opened over, falling back to
-- cwd — mirroring the shuck/needle search-root discovery. Prefers cwd when the
-- origin buffer lives under it, else the nearest `.git` above the buffer, else
-- cwd itself.
local function resolve_repo_root(buf_name)
  local cwd = vim.fn.getcwd()
  local buf_dir
  if not buf_name or buf_name == "" or buf_name:match("^%w+://") then
    buf_dir = cwd
  else
    buf_dir = vim.fs.dirname(buf_name)
  end
  if buf_dir == cwd or buf_dir:sub(1, #cwd + 1) == cwd .. "/" then
    local at_cwd = git_mod.discover_repo_root(cwd)
    if at_cwd then return at_cwd end
  end
  return git_mod.discover_repo_root(buf_dir) or cwd
end

-- A short, human-readable label for a diff: `<repo>/<branch> <base>..<target>`,
-- with the floating commit shown as `dirty`. Used for the listed buffer name.
local function diff_label(git, base, target)
  local repo = vim.fn.fnamemodify(git.repo_root, ":t")
  local branch = git:current_branch() or "?"
  local t = target == M.WORKTREE and "dirty" or target
  return ("%s/%s %s..%s"):format(repo, branch, base, t)
end

local Session = {}
Session.__index = Session

-- Content-addressed collapse keys (stable across re-diffs / reloads): a commit
-- by its sha, a file by sha+path, a combined file by path.
local function commit_key(sha) return "c:" .. sha end
local function file_key(sha, path) return "f:" .. sha .. "\0" .. path end
local function cfile_key(path) return "cf:" .. path end
local function seen_key(sha, path) return "s:" .. sha .. "\0" .. path end
local function cseen_key(path) return "cs:" .. path end

-- Build the review model for `base..target`: the net diff `files`, the ordered
-- `commits` (each with its own `commit_diff` files), and the `shas` to load from
-- the store. For a work-tree target the diff runs base->work tree and the
-- floating commit (tracked dirty edits + untracked files) is appended last.
local function build_model(git, base, target)
  local worktree = target == M.WORKTREE
  local files, err
  if worktree then
    files, err = git:diff_to_worktree(base)
  else
    files, err = git:combined_diff(base, target)
  end
  if not files then return nil, err end
  for _, f in ipairs(files) do f.collapsed = false end

  local commit_target = worktree and "HEAD" or target
  local commits, cerr = git:commits(base, commit_target)
  if not commits then return nil, cerr end
  local shas = {}
  for _, c in ipairs(commits) do
    c.files = git:commit_diff(c.sha) or {}
    shas[#shas + 1] = c.sha
  end

  if worktree then
    local ffiles = {}
    for _, f in ipairs(git:worktree_diff() or {}) do
      f.collapsed = false
      ffiles[#ffiles + 1] = f
    end
    for _, f in ipairs(git:untracked() or {}) do
      f.collapsed = false
      ffiles[#ffiles + 1] = f
    end
    commits[#commits + 1] = {
      sha = M.WORKTREE, summary = "uncommitted changes", files = ffiles, collapsed = false,
    }
    shas[#shas + 1] = M.WORKTREE
  end
  return files, commits, shas
end

local CHEVRON_OPEN = "▾"
local CHEVRON_CLOSED = "▸"

-- The new-file line range a hunk introduces. For a pure-deletion hunk
-- (new_count == 0) this is the synthetic anchor `max(new_start, 1)` -- the
-- new-file line just after the removed region -- so the deletion is markable
-- via the normal range/tuple paths. nil only when the hunk has no new_start.
local function hunk_new_range(hunk)
  if hunk.new_count and hunk.new_count > 0 then
    return { hunk.new_start, hunk.new_start + hunk.new_count - 1 }
  end
  if hunk.new_start then
    local a = math.max(hunk.new_start, 1)
    return { a, a }
  end
  return nil
end

-- The anchor new-file lines of a hunk: the new_lnum of each context/add line,
-- or for a pure-deletion hunk (no new lines) a single synthetic anchor
-- `max(new_start, 1)`.
local function hunk_anchor_lnums(hunk)
  local out = {}
  for _, dl in ipairs(hunk.lines) do
    if dl.new_lnum then out[#out + 1] = dl.new_lnum end
  end
  if #out == 0 and hunk.new_start then
    out[1] = math.max(hunk.new_start, 1)
  end
  return out
end

-- A hunk is "seen" iff it has at least one anchor line and every anchor resolves
-- to an adapter that reports it seen. `resolve(new_lnum) -> (adapter, key_lnum)`
-- returns nil for a line with no owner (which makes the hunk unseen).
local function hunk_is_seen(hunk, resolve)
  local anchors = hunk_anchor_lnums(hunk)
  if #anchors == 0 then return false end
  for _, ln in ipairs(anchors) do
    local ad, kl = resolve(ln)
    if not ad or not ad.is_seen(kl) then return false end
  end
  return true
end

-- All new-file ranges a file changes within one commit's diff.
local function file_new_ranges(file)
  local ranges = {}
  for _, hunk in ipairs(file.hunks) do
    local r = hunk_new_range(hunk)
    if r then ranges[#ranges + 1] = r end
  end
  return ranges
end

-- The addressing adapter for a (commit, path): real commits use the line-range
-- adapter; the floating commit uses the content-hash adapter, supplied the
-- working-tree file's current line texts so it can translate new_lnum ↔ content.
function Session:adapter_for(commit, path)
  if commit.sha == M.WORKTREE then
    return state_mod.hash_adapter(self.store, M.WORKTREE, path, self:worktree_lines(path))
  end
  return state_mod.range_adapter(self.store, commit.sha, path)
end

-- The addressing adapter for a combined-scope owner sha: the floating commit's
-- uncommitted lines (owner sha == WORKTREE, via blame's zero-sha remap) use the
-- content-hash adapter; every real commit uses the line-range adapter.
function Session:combined_adapter(sha, path)
  if sha == M.WORKTREE then
    return state_mod.hash_adapter(self.store, M.WORKTREE, path, self:worktree_lines(path))
  end
  return state_mod.range_adapter(self.store, sha, path)
end

-- The working-tree file's current lines (array indexed by new_lnum), cached.
-- This is the live content the floating commit's content hashes are matched
-- against; for both tracked-dirty and untracked files new_lnum == file line.
function Session:worktree_lines(path)
  self._wt_lines = self._wt_lines or {}
  if self._wt_lines[path] == nil then
    local abs = self.git.repo_root .. "/" .. path
    local ok, lines = pcall(vim.fn.readfile, abs)
    self._wt_lines[path] = (ok and lines) or {}
  end
  return self._wt_lines[path]
end

-- Is a file fully seen for (commit, path)? (every changed new-file range covered)
function Session:file_seen(commit, file)
  local ad = self:adapter_for(commit, file.path)
  for _, r in ipairs(file_new_ranges(file)) do
    if not ad.range_covered(r[1], r[2]) then return false end
  end
  return true
end

-- Is a whole commit fully seen?
function Session:commit_seen(commit)
  for _, file in ipairs(commit.files) do
    if not self:file_seen(commit, file) then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Combined overlay (Stage 4): per-line ownership via blame + tighter re-diff.
-- ---------------------------------------------------------------------------

-- Cached `git blame -p` provenance for a path at target: new_lnum -> {sha,orig}.
-- Depends only on target, so it survives seen-mark changes between renders.
function Session:provenance(path)
  self._prov = self._prov or {}
  if self._prov[path] == nil then
    -- A WORKTREE target blames the live work tree (nil ref); blame attributes
    -- uncommitted lines to the all-zero sha, which we remap to the floating id
    -- so they route to the content-hash adapter.
    local ref = self.target ~= M.WORKTREE and self.target or nil
    local out = self.git:blame(ref, path)
    local map = (out and provenance.parse_blame(out)) or {}
    if self.target == M.WORKTREE then
      provenance.map_zero_sha(map, M.WORKTREE)
    end
    self._prov[path] = map
  end
  return self._prov[path]
end

-- sha -> chronological index within base..target.
function Session:commit_index()
  if not self._cidx then
    self._cidx = {}
    for i, c in ipairs(self.commits) do self._cidx[c.sha] = i end
  end
  return self._cidx
end

-- The tighter re-diff over `Xe^..target` used to elide a seen prefix. For a
-- real target it is `git diff Xe^..target`. For the work-tree target the end is
-- the live work tree, so it is `git diff <from>` (two-dot to the work tree),
-- where `from` is `HEAD` when the earliest unseen contributor is the floating
-- commit itself (its parent is HEAD) and `Xe^` otherwise.
function Session:tighter_diff(xe, path)
  if self.target == M.WORKTREE then
    local from = (xe == M.WORKTREE) and "HEAD" or (xe .. "^")
    return self.git:diff_to_worktree(from, path)
  end
  return self.git:range_diff(xe .. "^", self.target, path)
end

-- Project the raw combined diff into display files, overlaying seen state:
-- fully-seen files collapse to a single "seen up to" row; partially-seen files
-- are re-diffed over the tighter Xe^..target range (Xe = earliest unseen
-- contributor) and filtered to hunks that still contain an unseen new line.
function Session:compute_combined()
  local cidx = self:commit_index()
  local out = {}
  for _, raw in ipairs(self.files) do
    local path = raw.path
    local cov = self.collapse[cfile_key(path)]
    if cov ~= nil then raw.collapsed = cov end
    local prov = self:provenance(path)
    local earliest_contrib, earliest_unseen, newest = nil, nil, nil
    local any_new, seen_count = false, 0
    for _, hunk in ipairs(raw.hunks) do
      for _, dl in ipairs(hunk.lines) do
        if dl.new_lnum then
          any_new = true
          local p = prov[dl.new_lnum]
          local idx = p and cidx[p.sha]
          if idx then
            if not earliest_contrib or idx < earliest_contrib then earliest_contrib = idx end
            if not newest or idx > newest then newest = idx end
            if self:combined_adapter(p.sha, path).is_seen(p.orig_lnum) then
              seen_count = seen_count + 1
            elseif not earliest_unseen or idx < earliest_unseen then
              earliest_unseen = idx
            end
          end
        end
      end
    end
    if not any_new or (earliest_unseen and seen_count == 0) then
      -- Nothing seen (or a pure-deletion file): show the full combined diff.
      out[#out + 1] = { path = path, kind = raw.kind, hunks = raw.hunks, raw = raw }
    elseif not earliest_unseen then
      out[#out + 1] = {
        path = path, kind = raw.kind, hunks = {}, raw = raw,
        fully_seen = true, seen_up_to = newest and self.commits[newest].sha,
      }
    else
      local xe = self.commits[earliest_unseen].sha
      local files = self:tighter_diff(xe, path)
      local rf = files and files[1]
      local hunks = {}
      if rf then
        for _, hunk in ipairs(rf.hunks) do
          local keep = false
          for _, dl in ipairs(hunk.lines) do
            local p = dl.new_lnum and prov[dl.new_lnum]
            if p and not self:combined_adapter(p.sha, path).is_seen(p.orig_lnum) then
              keep = true
              break
            end
          end
          if keep then hunks[#hunks + 1] = hunk end
        end
      end
      local has_prefix = seen_count > 0 and earliest_contrib and earliest_unseen > earliest_contrib
      out[#out + 1] = {
        path = path, kind = raw.kind, hunks = hunks, raw = raw,
        seen_up_to = has_prefix and xe or nil,
      }
    end
  end
  return out
end

-- The (sha, path, range) tuples a combined target addresses, grouped by owning
-- commit via provenance. A file header enumerates the whole raw file's new
-- lines; a hunk enumerates that display hunk's new lines.
function Session:combined_tuples(target)
  local cf = self.combined_files[target.cfile]
  local prov = self:provenance(cf.path)
  local lnums = {}
  if target.hunk then
    for _, dl in ipairs(cf.hunks[target.hunk].lines) do
      if dl.new_lnum then lnums[#lnums + 1] = dl.new_lnum end
    end
  else
    for _, hunk in ipairs(cf.raw.hunks) do
      for _, dl in ipairs(hunk.lines) do
        if dl.new_lnum then lnums[#lnums + 1] = dl.new_lnum end
      end
    end
  end
  local out = {}
  for _, ln in ipairs(lnums) do
    local p = prov[ln]
    if p then out[#out + 1] = { sha = p.sha, path = cf.path, range = { p.orig_lnum, p.orig_lnum } } end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Build (pure projection): returns lines, row_map, highlights, comments.
-- ---------------------------------------------------------------------------

function Session:build()
  local lines = {}
  local row_map = {}
  local highlights = {}
  local comments = {}
  local function emit(text, target, hl)
    lines[#lines + 1] = text
    local row = #lines - 1
    row_map[row] = target
    if hl then highlights[#highlights + 1] = { row = row, hl = hl } end
    return row
  end

  local function emit_hunk(hunk, hi, target_base, resolve)
    local target = vim.tbl_extend("force", target_base, { hunk = hi })
    emit(hunk.header, target, "GleanHunkHeader")
    for li, dl in ipairs(hunk.lines) do
      local marker = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
      local hl = dl.kind == "add" and "GleanAdd"
        or dl.kind == "del" and "GleanDel"
        or "GleanContext"
      local ad, kl = nil, nil
      if dl.new_lnum then ad, kl = resolve(dl.new_lnum) end
      if ad and ad.is_seen(kl) then hl = "GleanSeen" end
      local row = emit(marker .. dl.text,
        vim.tbl_extend("force", target, { line = li }), hl)
      if ad then
        local texts = ad.comments_at(kl)
        if #texts > 0 then comments[#comments + 1] = { row = row, texts = texts } end
      end
    end
  end

  local function emit_file_body(file, target_base, resolve, seen_ck)
    local seen_idx, unseen_idx = {}, {}
    for hi, hunk in ipairs(file.hunks) do
      if hunk_is_seen(hunk, resolve) then seen_idx[#seen_idx + 1] = hi
      else unseen_idx[#unseen_idx + 1] = hi end
    end
    for _, hi in ipairs(unseen_idx) do emit_hunk(file.hunks[hi], hi, target_base, resolve) end
    if #seen_idx > 0 then
      local c = self.collapse[seen_ck]; if c == nil then c = true end
      local chev = c and CHEVRON_CLOSED or CHEVRON_OPEN
      emit(("  %s ✓ seen (%d hunks)"):format(chev, #seen_idx),
        vim.tbl_extend("force", target_base, { seen = true }), "GleanSeen")
      if not c then
        for _, hi in ipairs(seen_idx) do emit_hunk(file.hunks[hi], hi, target_base, resolve) end
      end
    end
  end

  if self.scope == "commits" then
    for ci, commit in ipairs(self.commits) do
      local chevron = commit.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
      local mark = self:commit_seen(commit) and "✓" or "●"
      local short = commit.sha:sub(1, 8)
      emit(("%s %s %s %s"):format(chevron, mark, short, commit.summary),
        { commit = ci }, "GleanCommitHeader")
      if not commit.collapsed then
        for fi, file in ipairs(commit.files) do
          local fchev = file.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
          local fmark = self:file_seen(commit, file) and "✓" or " "
          local kind = file.kind and (" [" .. file.kind .. "]") or ""
          emit(("  %s %s %s%s"):format(fchev, fmark, file.path, kind),
            { commit = ci, file = fi }, "GleanFileHeader")
          if not file.collapsed then
            local adapter = self:adapter_for(commit, file.path)
            local resolve = function(ln) return adapter, ln end
            emit_file_body(file, { commit = ci, file = fi }, resolve,
              seen_key(commit.sha, file.path))
          end
        end
      end
    end
  else
    self.combined_files = self:compute_combined()
    for fi, cf in ipairs(self.combined_files) do
      if cf.fully_seen then
        emit(("✓ %s  ⟶ seen up to %s"):format(cf.path, (cf.seen_up_to or ""):sub(1, 8)),
          { cfile = fi }, "GleanSeen")
      else
        local chevron = cf.raw.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
        local kind = cf.kind and (" [" .. cf.kind .. "]") or ""
        emit(chevron .. " " .. cf.path .. kind, { cfile = fi }, "GleanFileHeader")
        if not cf.raw.collapsed then
          if cf.seen_up_to then
            emit(("  ⟶ seen up to %s^"):format(cf.seen_up_to:sub(1, 8)),
              { cfile = fi, marker = true }, "GleanSeen")
          end
          local prov = self:provenance(cf.path)
          for hi, hunk in ipairs(cf.hunks) do
            local target = { cfile = fi, hunk = hi }
            emit(hunk.header, target, "GleanHunkHeader")
            for li, dl in ipairs(hunk.lines) do
              local marker = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
              local hl = dl.kind == "add" and "GleanAdd"
                or dl.kind == "del" and "GleanDel"
                or "GleanContext"
              local owner = dl.new_lnum and prov[dl.new_lnum]
              local owner_ad = owner and self:combined_adapter(owner.sha, cf.path)
              if owner_ad and owner_ad.is_seen(owner.orig_lnum) then
                hl = "GleanSeen"
              end
              local row = emit(marker .. dl.text,
                vim.tbl_extend("force", target, { line = li }), hl)
              if owner_ad then
                local texts = owner_ad.comments_at(owner.orig_lnum)
                if #texts > 0 then comments[#comments + 1] = { row = row, texts = texts } end
              end
            end
          end
        end
      end
    end
  end

  return lines, row_map, highlights, comments
end

function Session:render()
  local lines, row_map, highlights, comments = self:build()
  self.row_map = row_map
  local win = self.win
  local cur
  if win and api.nvim_win_is_valid(win) then
    cur = api.nvim_win_get_cursor(win)
  end
  api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = self.buf })
  api.nvim_buf_clear_namespace(self.buf, NS, 0, -1)
  for _, hl in ipairs(highlights) do
    api.nvim_buf_set_extmark(self.buf, NS, hl.row, 0, {
      end_row = hl.row + 1,
      end_col = 0,
      hl_group = hl.hl,
      hl_eol = true,
    })
  end
  api.nvim_buf_clear_namespace(self.buf, COMMENT_NS, 0, -1)
  for _, c in ipairs(comments) do
    local virt_lines = {}
    for _, t in ipairs(c.texts) do
      virt_lines[#virt_lines + 1] = { { "    💬 " .. t.text, "GleanComment" } }
    end
    api.nvim_buf_set_extmark(self.buf, COMMENT_NS, c.row, 0, {
      virt_lines = virt_lines,
    })
  end
  if cur then
    local last = math.max(1, #lines)
    cur[1] = math.min(cur[1], last)
    pcall(api.nvim_win_set_cursor, win, cur)
  end
end

-- ---------------------------------------------------------------------------
-- Collapse (ephemeral) — initialized from seen, then independent.
-- ---------------------------------------------------------------------------

-- Apply commit-scope collapse: an explicit user override (content-addressed in
-- self.collapse) wins; otherwise the default is "collapsed iff fully seen" so
-- only unseen work is expanded. Overrides persist across reloads/reopens.
function Session:apply_collapse()
  for _, commit in ipairs(self.commits) do
    local ov = self.collapse[commit_key(commit.sha)]
    commit.collapsed = ov ~= nil and ov or self:commit_seen(commit)
    for _, file in ipairs(commit.files) do
      local fov = self.collapse[file_key(commit.sha, file.path)]
      file.collapsed = fov ~= nil and fov or self:file_seen(commit, file)
    end
  end
end

function Session:cursor_row()
  if self.win and api.nvim_win_is_valid(self.win) then
    return api.nvim_win_get_cursor(self.win)[1] - 1
  end
  return 0
end

function Session:toggle_collapse(row)
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  if not target then return end
  if self.scope == "commits" then
    local commit = self.commits[target.commit]
    if target.file then
      local file = commit.files[target.file]
      file.collapsed = not file.collapsed
      self.collapse[file_key(commit.sha, file.path)] = file.collapsed
    else
      commit.collapsed = not commit.collapsed
      self.collapse[commit_key(commit.sha)] = commit.collapsed
    end
  else
    if target.cfile then
      local cf = self.combined_files[target.cfile]
      if cf and not cf.fully_seen then
        cf.raw.collapsed = not cf.raw.collapsed
        self.collapse[cfile_key(cf.path)] = cf.raw.collapsed
      end
    end
  end
  self:render()
end

-- ---------------------------------------------------------------------------
-- Seen marks (commit scope) — authored against (commit_sha, path, new range).
-- ---------------------------------------------------------------------------

-- The (commit_sha, path, range) tuples a target row addresses. A commit header
-- yields every file's changed ranges; a file header yields that file's ranges;
-- a hunk/line yields that hunk's range.
function Session:target_ranges(target)
  local commit = self.commits[target.commit]
  local out = {}
  if target.file then
    local file = commit.files[target.file]
    if target.hunk then
      local r = hunk_new_range(file.hunks[target.hunk])
      if r then out[#out + 1] = { sha = commit.sha, path = file.path, range = r } end
    else
      for _, r in ipairs(file_new_ranges(file)) do
        out[#out + 1] = { sha = commit.sha, path = file.path, range = r }
      end
    end
  else
    for _, file in ipairs(commit.files) do
      for _, r in ipairs(file_new_ranges(file)) do
        out[#out + 1] = { sha = commit.sha, path = file.path, range = r }
      end
    end
  end
  return out
end

-- The (commit, path, new_lnum list) groups a target row addresses, mirroring
-- target_ranges but carrying the owning commit object (so the right addressing
-- adapter is chosen) and explicit new-file line numbers. A commit header yields
-- every file's lines; a file header that file's lines; a hunk that hunk's lines.
function Session:target_groups(target)
  local commit = self.commits[target.commit]
  local groups = {}
  local function add_file(file, ranges)
    local lnums = {}
    for _, r in ipairs(ranges) do
      for l = r[1], r[2] do lnums[#lnums + 1] = l end
    end
    if #lnums > 0 then groups[#groups + 1] = { commit = commit, file = file, lnums = lnums } end
  end
  if target.file then
    local file = commit.files[target.file]
    if target.hunk then
      local r = hunk_new_range(file.hunks[target.hunk])
      add_file(file, r and { r } or {})
    else
      add_file(file, file_new_ranges(file))
    end
  else
    for _, file in ipairs(commit.files) do add_file(file, file_new_ranges(file)) end
  end
  return groups
end

-- Toggle seen on the cursor's target: if every addressed line is already seen,
-- unmark them; otherwise mark them all. Commit scope routes through the per-
-- commit addressing adapter (range for real commits, content-hash for the
-- floating commit); combined scope keeps the provenance range path. Persists
-- the affected commit shards.
function Session:toggle_seen(row)
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  if not target then return end
  local touched = {}
  if self.scope == "commits" then
    if not target.commit then return end
    local groups = self:target_groups(target)
    if #groups == 0 then return end
    local all_seen = true
    for _, g in ipairs(groups) do
      local ad = self:adapter_for(g.commit, g.file.path)
      for _, l in ipairs(g.lnums) do
        if not ad.is_seen(l) then all_seen = false break end
      end
      if not all_seen then break end
    end
    for _, g in ipairs(groups) do
      local ad = self:adapter_for(g.commit, g.file.path)
      if all_seen then ad.unmark(g.lnums) else ad.mark(g.lnums) end
      touched[g.commit.sha] = true
    end
  else
    if not target.cfile then return end
    local tuples = self:combined_tuples(target)
    if #tuples == 0 then return end
    -- Group single-line tuples by owning commit so committed lines route to the
    -- range adapter and uncommitted (WORKTREE-owned) lines to the hash adapter.
    local groups = {}
    for _, t in ipairs(tuples) do
      local key = t.sha .. "\0" .. t.path
      groups[key] = groups[key] or { sha = t.sha, path = t.path, lnums = {} }
      local g = groups[key]
      g.lnums[#g.lnums + 1] = t.range[1]
    end
    local all_seen = true
    for _, g in pairs(groups) do
      local ad = self:combined_adapter(g.sha, g.path)
      for _, l in ipairs(g.lnums) do
        if not ad.is_seen(l) then all_seen = false break end
      end
      if not all_seen then break end
    end
    for _, g in pairs(groups) do
      local ad = self:combined_adapter(g.sha, g.path)
      if all_seen then ad.unmark(g.lnums) else ad.mark(g.lnums) end
      touched[g.sha] = true
    end
  end
  for sha in pairs(touched) do self.store:save_commit(sha) end
  self:render()
end

-- Mark a visual span of diff rows seen: translate each row's diff line to its
-- new_lnum, group by (commit, path), and store exactly those ranges (sub-hunk).
-- Deletion-only rows contribute no new-file line and are skipped.
function Session:mark_visual_range(srow, erow)
  if srow > erow then srow, erow = erow, srow end
  local touched = {}
  if self.scope == "commits" then
    -- Group by (commit, file), collect new_lnums, and mark via the adapter so
    -- the floating commit's content hashing kicks in for uncommitted lines.
    local groups = {}
    for row = srow, erow do
      local target = self.row_map[row]
      if target and target.commit and target.file and target.line then
        local commit = self.commits[target.commit]
        local file = commit.files[target.file]
        local dl = file.hunks[target.hunk].lines[target.line]
        if dl.new_lnum then
          local key = target.commit .. "\0" .. file.path
          groups[key] = groups[key] or { commit = commit, file = file, lnums = {} }
          groups[key].lnums[#groups[key].lnums + 1] = dl.new_lnum
        end
      end
    end
    for _, g in pairs(groups) do
      self:adapter_for(g.commit, g.file.path).mark(g.lnums)
      touched[g.commit.sha] = true
    end
  else
    local groups = {}
    for row = srow, erow do
      local target = self.row_map[row]
      if target and target.cfile and target.hunk and target.line then
        local cf = self.combined_files[target.cfile]
        local dl = cf.hunks[target.hunk].lines[target.line]
        local p = dl.new_lnum and self:provenance(cf.path)[dl.new_lnum]
        if p then
          local key = p.sha .. "\0" .. cf.path
          groups[key] = groups[key] or { sha = p.sha, path = cf.path, lnums = {} }
          groups[key].lnums[#groups[key].lnums + 1] = p.orig_lnum
        end
      end
    end
    for _, g in pairs(groups) do
      self:combined_adapter(g.sha, g.path).mark(g.lnums)
      touched[g.sha] = true
    end
  end
  for sha in pairs(touched) do self.store:save_commit(sha) end
  self:render()
end

-- ---------------------------------------------------------------------------
-- Comments (commit scope) — anchored to (commit_sha, path, new_lnum).
-- ---------------------------------------------------------------------------

-- Resolve a row to (sha, path, new_lnum). A deletion row (no new_lnum) anchors
-- to the nearest surviving new-file line in its hunk.
-- Find the new_lnum to anchor a comment on: the row's own new_lnum, else the
-- nearest surviving new-file line in its hunk (forward then backward).
local function anchor_lnum(hunk, idx)
  local dl = hunk.lines[idx]
  if dl.new_lnum then return dl.new_lnum end
  for li = idx, #hunk.lines do
    if hunk.lines[li].new_lnum then return hunk.lines[li].new_lnum end
  end
  for li = idx, 1, -1 do
    if hunk.lines[li].new_lnum then return hunk.lines[li].new_lnum end
  end
  return nil
end

-- Resolve a row to (adapter, new_lnum, save_sha): the addressing adapter to
-- author the comment through, the new-file line number to anchor it to, and the
-- shard id to persist. Commit scope picks the owning commit's adapter; combined
-- scope routes to the provenance owner via a range adapter.
function Session:comment_anchor(row)
  local target = self.row_map[row]
  if not target or not target.line then return nil end
  if self.scope == "commits" then
    if not target.commit then return nil end
    local commit = self.commits[target.commit]
    local file = commit.files[target.file]
    local lnum = anchor_lnum(file.hunks[target.hunk], target.line)
    if not lnum then return nil end
    return self:adapter_for(commit, file.path), lnum, commit.sha
  else
    if not target.cfile then return nil end
    local cf = self.combined_files[target.cfile]
    local lnum = anchor_lnum(cf.hunks[target.hunk], target.line)
    local p = lnum and self:provenance(cf.path)[lnum]
    if not p then return nil end
    return self:combined_adapter(p.sha, cf.path), p.orig_lnum, p.sha
  end
end

function Session:add_comment_at(row, text)
  if row == nil then row = self:cursor_row() end
  if not text or text == "" then return end
  local ad, lnum, save_sha = self:comment_anchor(row)
  if not ad then return end
  ad.add_comment(lnum, text)
  self.store:save_commit(save_sha)
  self:render()
end

-- ---------------------------------------------------------------------------
-- Jump-to-source (Stage 5).
-- ---------------------------------------------------------------------------

-- Resolve a cursor row to the source line it points at:
--   { ref, path, lnum } where the line we review (add/context) resolves to its
--   new-file line in the post-image ref, and a deletion resolves to its old
--   line in the pre-image ref. The ref is the commit's sha (commit scope) or
--   target/base (combined scope).
function Session:jump_target(row)
  local target = self.row_map[row]
  if not target or not target.line then return nil end
  local dl, path, post_ref, pre_ref
  if self.scope == "commits" then
    if not target.commit then return nil end
    local commit = self.commits[target.commit]
    local file = commit.files[target.file]
    dl = file.hunks[target.hunk].lines[target.line]
    path = file.path
    -- The floating commit's add/context lines live in the live work tree; its
    -- pre-image (deletions) resolves against HEAD.
    if commit.sha == M.WORKTREE then
      post_ref, pre_ref = M.WORKTREE, "HEAD"
    else
      post_ref, pre_ref = commit.sha, commit.sha .. "^"
    end
  else
    if not target.cfile then return nil end
    local cf = self.combined_files[target.cfile]
    dl = cf.hunks[target.hunk].lines[target.line]
    path = cf.path
    post_ref, pre_ref = self.target, self.base
  end
  if not dl then return nil end
  if dl.kind == "del" then
    return { ref = pre_ref, path = path, lnum = dl.old_lnum or 1, is_del = true }
  end
  return { ref = post_ref, path = path, lnum = dl.new_lnum or 1 }
end

-- True when `ref` resolves to the currently checked-out HEAD commit, so the
-- working-tree file can be opened directly (LSP attaches).
function Session:ref_is_head(ref)
  local head = self.git:rev_parse("HEAD")
  if not head then return false end
  local resolved = self.git:rev_parse(ref)
  return resolved ~= nil and resolved == head
end

-- Jump to the resolved source line. Opens the live working-tree file when its
-- ref is HEAD (so LSP/navigation work), otherwise a read-only scratch buffer
-- populated from `git show ref:path`, with filetype inferred from the path.
function Session:jump(row)
  if row == nil then row = self:cursor_row() end
  local jt = self:jump_target(row)
  if not jt then return end
  local win = self.win
  local abs = self.git.repo_root .. "/" .. jt.path
  -- Only post-image (add/context) rows live in the working tree; a deletion must
  -- always read its pre-image via `git show`. The floating commit's post-image
  -- ref is the live work tree directly; otherwise open live when ref is HEAD.
  local live = not jt.is_del and (jt.ref == M.WORKTREE or self:ref_is_head(jt.ref))
  if live and vim.fn.filereadable(abs) == 1 then
    if win and api.nvim_win_is_valid(win) then api.nvim_set_current_win(win) end
    vim.cmd("edit " .. vim.fn.fnameescape(abs))
    pcall(api.nvim_win_set_cursor, 0, { jt.lnum, 0 })
    return abs
  end
  local content = self.git:show(jt.ref, jt.path) or ""
  local buf = api.nvim_create_buf(false, true)
  local lines = vim.split(content, "\n", { plain = true })
  if lines[#lines] == "" then lines[#lines] = nil end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  local ft = vim.filetype.match({ filename = jt.path, contents = lines })
  if ft then api.nvim_set_option_value("filetype", ft, { buf = buf }) end
  pcall(api.nvim_buf_set_name, buf, "glean-show://" .. buf .. ":" .. jt.ref:sub(1, 8) .. ":" .. jt.path)
  if win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
    api.nvim_win_set_buf(win, buf)
  end
  pcall(api.nvim_win_set_cursor, 0, { jt.lnum, 0 })
  return buf
end

-- ---------------------------------------------------------------------------
-- Scope switching.
-- ---------------------------------------------------------------------------

function Session:set_scope(scope)
  if scope == self.scope then return end
  self.scope = scope
  if scope == "commits" then self:apply_collapse() end
  self:render()
end

function Session:toggle_scope()
  self:set_scope(self.scope == "commits" and "combined" or "commits")
end

-- ---------------------------------------------------------------------------
-- Live update (work-tree target) — poll the repo and re-render in place.
-- ---------------------------------------------------------------------------

-- Rebuild the model from the current repo state and re-render, preserving the
-- content-addressed collapse overrides, the cursor, and (via immediate saves)
-- all authored seen/comments. Reloads the store from disk and clears the
-- per-target memoized caches so the projection reflects the latest content.
function Session:reload()
  if not api.nvim_buf_is_valid(self.buf) then return end
  local files, commits, shas = build_model(self.git, self.base, self.target)
  if not files then return end
  local store = state_mod.new({ dir = self.state_dir })
  store:load(shas)
  self.files = files
  self.commits = commits
  self.store = store
  self._wt_lines = nil
  self._prov = nil
  self._cidx = nil
  self.combined_files = nil
  self:apply_collapse()
  self:render()
end

-- Start polling the repo on a timer; only the live work-tree review opts in.
-- Each tick compares a cheap dirty signature and reloads only when it changed,
-- so an idle buffer does no rebuild work and the cursor never jumps.
function Session:start_live()
  if not self.worktree or self._timer then return end
  self._sig = self.git:dirty_sig()
  local timer = vim.uv.new_timer()
  self._timer = timer
  timer:start(LIVE_INTERVAL_MS, LIVE_INTERVAL_MS, function()
    vim.schedule(function()
      if not api.nvim_buf_is_valid(self.buf) then self:stop_live() return end
      local sig = self.git:dirty_sig()
      if sig ~= self._sig then
        self._sig = sig
        self:reload()
      end
    end)
  end)
end

function Session:stop_live()
  if self._timer then
    self._timer:stop()
    if not self._timer:is_closing() then self._timer:close() end
    self._timer = nil
  end
end

-- ---------------------------------------------------------------------------
-- Keymaps / open.
-- ---------------------------------------------------------------------------

local function setup_keymaps(buf, session)
  local function map(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("n", "=", function() session:toggle_collapse() end)
  map("n", "m", function() session:toggle_seen() end)
  map("x", "m", function()
    local srow = vim.fn.getpos("v")[2] - 1
    local erow = vim.fn.getpos(".")[2] - 1
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    session:mark_visual_range(srow, erow)
  end)
  map("n", "c", function()
    vim.ui.input({ prompt = "glean comment: " }, function(text)
      if text then session:add_comment_at(nil, text) end
    end)
  end)
  map("n", "<CR>", function() session:jump() end)
  map("n", "S", function() session:toggle_scope() end)
  map("n", "q", function()
    if api.nvim_win_is_valid(session.win) then
      api.nvim_win_close(session.win, true)
    end
  end)
end

-- Open a review of `base...target`. `opts`:
--   - base, target (required): refs to diff.
--   - repo_root, run (optional): injected for tests.
--   - scope (optional, default "combined").
--   - state_dir (optional): override the ReviewStore directory (tests).
--   - open_window (optional, default true).

function M.open(opts)
  assert(opts and opts.base and opts.target, "glean.open requires base and target")
  local repo_root = opts.repo_root
    or resolve_repo_root(api.nvim_buf_get_name(0))
  assert(repo_root, "glean: could not find a git repo root")
  local git = git_mod.new({ repo_root = repo_root, run = opts.run })

  local worktree = opts.target == M.WORKTREE
  local files, commit_list, shas = build_model(git, opts.base, opts.target)
  if not files then error("glean: build_model failed: " .. tostring(commit_list)) end

  local store = state_mod.new({ dir = opts.state_dir })
  store:load(shas)

  -- One buffer per (repo, base, target); reuse it on reopen. The live work-tree
  -- review is a "special" unlisted buffer (it tracks the current repo state and
  -- auto-refreshes); committed-range diffs are persistent and listed.
  local key = buffer_key(repo_root, opts.base, opts.target)
  local existing = buffers[key]
  local buf
  if existing and api.nvim_buf_is_valid(existing) then
    buf = existing
  else
    buf = api.nvim_create_buf(not worktree, false)
    api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
    api.nvim_set_option_value("swapfile", false, { buf = buf })
    api.nvim_set_option_value("filetype", "glean", { buf = buf })
    pcall(api.nvim_buf_set_name, buf, "Glean:" .. diff_label(git, opts.base, opts.target))
    buffers[key] = buf
    api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
      buffer = buf,
      callback = function()
        buffers[key] = nil
        views[key] = nil
        local s = sessions[key]
        if s then s:stop_live() end
        sessions[key] = nil
      end,
    })
  end
  api.nvim_set_option_value("buflisted", not worktree, { buf = buf })

  -- Collapse overrides are content-addressed and kept in process memory keyed by
  -- the buffer, so neither a live reload-from-disk nor a reopen loses the user's
  -- expand/collapse choices.
  local collapse = views[key] or {}
  views[key] = collapse

  local prev = sessions[key]
  if prev then prev:stop_live() end

  local session = setmetatable({
    git = git,
    store = store,
    base = opts.base,
    target = opts.target,
    worktree = worktree,
    state_dir = opts.state_dir,
    files = files,
    commits = commit_list,
    scope = opts.scope or "combined",
    buf = buf,
    win = nil,
    row_map = {},
    collapse = collapse,
  }, Session)
  sessions[key] = session
  session:apply_collapse()

  local open_window = opts.open_window ~= false
  if open_window then
    -- Reuse a window already showing this buffer in the current tabpage,
    -- otherwise open a fresh tab.
    local shown
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if api.nvim_win_get_buf(w) == buf then shown = w break end
    end
    if shown then
      session.win = shown
      api.nvim_set_current_win(shown)
    else
      -- Take over the current window, unless it isn't full height (something
      -- above or below it) or is a floating window. In that case add a new
      -- full-height column on the right so the review doesn't squash into a
      -- partial pane.
      local is_floating = api.nvim_win_get_config(0).relative ~= ""
      if is_floating
        or vim.fn.winnr("k") ~= vim.fn.winnr()
        or vim.fn.winnr("j") ~= vim.fn.winnr()
      then
        vim.cmd("botright vsplit")
      end
      session.win = api.nvim_get_current_win()
      api.nvim_win_set_buf(session.win, buf)
    end
    setup_keymaps(buf, session)
    session:start_live()
  end

  session:render()
  return session
end

-- Resolve the base/target for "current branch + dirty", with the live work tree
-- (the floating commit) as the target. On a feature branch the base is the fork
-- point from the default trunk (merge-base), so the review shows commits unique
-- to the branch plus uncommitted edits. On the default branch itself there is no
-- meaningful fork point, so the base is the upstream tracking ref (e.g.
-- origin/main), yielding unpushed commits plus uncommitted edits.
function M.resolve_dirty(git)
  local base
  if git:current_branch() == M.config.default_base then
    base = git:upstream()
  else
    base = git:merge_base(M.config.default_base, "HEAD")
  end
  return base or M.config.default_base, M.WORKTREE
end

-- Open a review of "current branch + dirty" with no base/target args.
function M.open_dirty(opts)
  opts = opts or {}
  local repo_root = opts.repo_root
    or resolve_repo_root(api.nvim_buf_get_name(0))
  assert(repo_root, "glean: could not find a git repo root")
  local git = git_mod.new({ repo_root = repo_root, run = opts.run })
  local base, target = M.resolve_dirty(git)
  return M.open(vim.tbl_extend("force", opts, {
    repo_root = repo_root, base = base, target = target,
  }))
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  api.nvim_set_hl(0, "GleanFileHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanCommitHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanHunkHeader", { link = "Comment", default = true })
  api.nvim_set_hl(0, "GleanAdd", { link = "DiffAdd", default = true })
  api.nvim_set_hl(0, "GleanDel", { link = "DiffDelete", default = true })
  api.nvim_set_hl(0, "GleanContext", { link = "Normal", default = true })
  api.nvim_set_hl(0, "GleanSeen", { link = "Comment", default = true })
  api.nvim_set_hl(0, "GleanComment", { link = "WarningMsg", default = true })
  api.nvim_create_user_command("Glean", function(o)
    if o.bang then
      M.open_dirty()
      return
    end
    local args = o.fargs
    if #args == 0 then
      M.open_dirty()
      return
    end
    local base = args[1] or M.config.default_base
    local target = args[2] or "HEAD"
    M.open({ base = base, target = target })
  end, { nargs = "*", bang = true })
  api.nvim_create_user_command("GleanDirty", function()
    M.open_dirty()
  end, {})
end

return M
