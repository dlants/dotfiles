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

local Session = {}
Session.__index = Session

local CHEVRON_OPEN = "▾"
local CHEVRON_CLOSED = "▸"

-- The new-file line range a hunk introduces, or nil for a pure-deletion hunk
-- (new_count == 0) which addresses no new-file line.
local function hunk_new_range(hunk)
  if hunk.new_count and hunk.new_count > 0 then
    return { hunk.new_start, hunk.new_start + hunk.new_count - 1 }
  end
  return nil
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
    local out = self.git:blame(self.target, path)
    self._prov[path] = (out and provenance.parse_blame(out)) or {}
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

-- Project the raw combined diff into display files, overlaying seen state:
-- fully-seen files collapse to a single "seen up to" row; partially-seen files
-- are re-diffed over the tighter Xe^..target range (Xe = earliest unseen
-- contributor) and filtered to hunks that still contain an unseen new line.
function Session:compute_combined()
  local cidx = self:commit_index()
  local out = {}
  for _, raw in ipairs(self.files) do
    local path = raw.path
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
            if state_mod.covers(self.store:seen_ranges(p.sha, path), p.orig_lnum) then
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
      local files = self.git:range_diff(xe .. "^", self.target, path)
      local rf = files and files[1]
      local hunks = {}
      if rf then
        for _, hunk in ipairs(rf.hunks) do
          local keep = false
          for _, dl in ipairs(hunk.lines) do
            local p = dl.new_lnum and prov[dl.new_lnum]
            if p and not state_mod.covers(self.store:seen_ranges(p.sha, path), p.orig_lnum) then
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

  local function emit_file_body(adapter, fi, file, target_base)
    for hi, hunk in ipairs(file.hunks) do
      local target = vim.tbl_extend("force", target_base, { hunk = hi })
      emit(hunk.header, target, "GleanHunkHeader")
      for li, dl in ipairs(hunk.lines) do
        local marker = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
        local hl = dl.kind == "add" and "GleanAdd"
          or dl.kind == "del" and "GleanDel"
          or "GleanContext"
        if adapter and dl.new_lnum and adapter.is_seen(dl.new_lnum) then
          hl = "GleanSeen"
        end
        local row = emit(marker .. dl.text,
          vim.tbl_extend("force", target, { line = li }), hl)
        if adapter and dl.new_lnum then
          local texts = adapter.comments_at(dl.new_lnum)
          if #texts > 0 then comments[#comments + 1] = { row = row, texts = texts } end
        end
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
            emit_file_body(self:adapter_for(commit, file.path), fi, file,
              { commit = ci, file = fi })
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
              if owner and state_mod.covers(self.store:seen_ranges(owner.sha, cf.path), owner.orig_lnum) then
                hl = "GleanSeen"
              end
              local row = emit(marker .. dl.text,
                vim.tbl_extend("force", target, { line = li }), hl)
              if owner then
                local texts = self.store:comments_at(owner.sha, cf.path, owner.orig_lnum)
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

-- (Re)initialize commit-scope collapse from seen status: fully-seen commits and
-- files start collapsed so only unseen work is expanded. Never persisted.
function Session:init_collapse()
  for _, commit in ipairs(self.commits) do
    commit.collapsed = self:commit_seen(commit)
    for _, file in ipairs(commit.files) do
      file.collapsed = self:file_seen(commit, file)
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
      commit.files[target.file].collapsed = not commit.files[target.file].collapsed
    else
      commit.collapsed = not commit.collapsed
    end
  else
    if target.cfile then
      local cf = self.combined_files[target.cfile]
      if cf and not cf.fully_seen then cf.raw.collapsed = not cf.raw.collapsed end
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
    local all_seen = true
    for _, t in ipairs(tuples) do
      if not state_mod.range_covered(self.store:seen_ranges(t.sha, t.path), t.range) then
        all_seen = false
        break
      end
    end
    for _, t in ipairs(tuples) do
      if all_seen then
        self.store:unmark_seen(t.sha, t.path, t.range)
      else
        self.store:mark_seen(t.sha, t.path, t.range)
      end
      touched[t.sha] = true
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
      for _, l in ipairs(g.lnums) do
        self.store:mark_seen(g.sha, g.path, { l, l })
      end
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
    return state_mod.range_adapter(self.store, p.sha, cf.path), p.orig_lnum, p.sha
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
    post_ref, pre_ref = commit.sha, commit.sha .. "^"
  else
    if not target.cfile then return nil end
    local cf = self.combined_files[target.cfile]
    dl = cf.hunks[target.hunk].lines[target.line]
    path = cf.path
    post_ref, pre_ref = self.target, self.base
  end
  if not dl then return nil end
  if dl.kind == "del" then
    return { ref = pre_ref, path = path, lnum = dl.old_lnum or 1 }
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
  if self:ref_is_head(jt.ref) and vim.fn.filereadable(abs) == 1 then
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
  if scope == "commits" then self:init_collapse() end
  self:render()
end

function Session:toggle_scope()
  self:set_scope(self.scope == "commits" and "combined" or "commits")
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
    or git_mod.discover_repo_root(api.nvim_buf_get_name(0))
  assert(repo_root, "glean: could not find a git repo root")
  local git = git_mod.new({ repo_root = repo_root, run = opts.run })

  -- When the target is the floating commit, the working tree is the net target:
  -- the combined diff runs base->work tree and the commit list is base..HEAD with
  -- the floating commit appended last (combined overlay routing lands in Stage 4).
  local worktree = opts.target == M.WORKTREE
  local files, err
  if worktree then
    files, err = git:diff_to_worktree(opts.base)
  else
    files, err = git:combined_diff(opts.base, opts.target)
  end
  if not files then error("glean: combined_diff failed: " .. tostring(err)) end
  for _, f in ipairs(files) do f.collapsed = false end

  local commit_target = worktree and "HEAD" or opts.target
  local commit_list, cerr = git:commits(opts.base, commit_target)
  if not commit_list then error("glean: commits failed: " .. tostring(cerr)) end
  local shas = {}
  for _, c in ipairs(commit_list) do
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
    commit_list[#commit_list + 1] = {
      sha = M.WORKTREE, summary = "uncommitted changes", files = ffiles, collapsed = false,
    }
    shas[#shas + 1] = M.WORKTREE
  end

  local store = state_mod.new({ dir = opts.state_dir })
  store:load(shas)

  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_set_option_value("filetype", "glean", { buf = buf })
  pcall(api.nvim_buf_set_name, buf, "glean://" .. buf .. ":" .. opts.base .. "..." .. opts.target)

  local session = setmetatable({
    git = git,
    store = store,
    base = opts.base,
    target = opts.target,
    files = files,
    commits = commit_list,
    scope = opts.scope or "combined",
    buf = buf,
    win = nil,
    row_map = {},
  }, Session)
  session:init_collapse()

  local open_window = opts.open_window ~= false
  if open_window then
    vim.cmd("tabnew")
    session.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(session.win, buf)
    setup_keymaps(buf, session)
  end

  session:render()
  return session
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
    local args = o.fargs
    local base = args[1] or M.config.default_base
    local target = args[2] or "HEAD"
    M.open({ base = base, target = target })
  end, { nargs = "*" })
end

return M
