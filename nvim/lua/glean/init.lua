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

-- The anchor new-file lines of a hunk: the new_lnum of each ADD line (the lines
-- this hunk actually introduces). Context lines are excluded because under the
-- combined per-line ownership model they may be owned by commits outside the
-- displayed base..target range (whose seen-state is neither tracked nor
-- persisted), which would make a hunk impossible to mark fully seen. For a hunk
-- with no add lines (a deletion that carries only context + deletions) we fall
-- back to its context new_lnums so the deletion follows its surrounding lines;
-- and for a pure-deletion hunk (no new lines at all) a single synthetic anchor
-- `max(new_start, 1)` -- the new-file line just after the removed region.
local function hunk_anchor_lnums(hunk)
  local out = {}
  for _, dl in ipairs(hunk.lines) do
    if dl.kind == "add" and dl.new_lnum then out[#out + 1] = dl.new_lnum end
  end
  if #out == 0 then
    for _, dl in ipairs(hunk.lines) do
      if dl.new_lnum then out[#out + 1] = dl.new_lnum end
    end
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

-- Project the raw combined diff into display files. Seen hunks are now rendered
-- in a collapsible per-file "seen" section by the shared body renderer, so this
-- is a thin pass that only applies the file-collapse override and exposes the
-- raw base..target hunks.
function Session:compute_combined()
  local out = {}
  for _, raw in ipairs(self.files) do
    local cov = self.collapse[cfile_key(raw.path)]
    if cov ~= nil then raw.collapsed = cov end
    out[#out + 1] = { path = raw.path, kind = raw.kind, hunks = raw.hunks, raw = raw }
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

-- The set of "sha\0orig_lnum" owners present in the target, derived from blame
-- provenance. A line authored on (commit, lnum) survives into the current
-- target iff blame still attributes some target line to that exact owner; if a
-- later commit overwrote it, blame names the later commit and the original is
-- "outdated". Cached per path.
function Session:present_owners(path)
  self._present = self._present or {}
  if self._present[path] == nil then
    local set = {}
    for _, p in pairs(self:provenance(path)) do
      set[p.sha .. "\0" .. p.orig_lnum] = true
    end
    self._present[path] = set
  end
  return self._present[path]
end

-- Gather every stored comment across all commits, grouped by file path. Walks
-- each commit's own diff (where comments are authored, against a stable
-- (sha, path, new_lnum)) so each comment carries its affected line's text. A
-- comment whose line no longer appears in the target is flagged `outdated` with
-- the short sha of the commit it came from. Returns { order = {paths},
-- by_path = { [path] = { sorted entries } } }.
function Session:collect_comments()
  local by_path = {}
  local order = {}
  for _, commit in ipairs(self.commits) do
    for _, file in ipairs(commit.files) do
      local adapter = self:adapter_for(commit, file.path)
      for _, hunk in ipairs(file.hunks) do
        for _, dl in ipairs(hunk.lines) do
          if dl.new_lnum then
            local texts = adapter.comments_at(dl.new_lnum)
            if #texts > 0 then
              local present = commit.sha == M.WORKTREE
                or self:present_owners(file.path)[commit.sha .. "\0" .. dl.new_lnum]
              if not by_path[file.path] then
                by_path[file.path] = {}
                order[#order + 1] = file.path
              end
              by_path[file.path][#by_path[file.path] + 1] = {
                lnum = dl.new_lnum,
                line = dl.text,
                short = commit.sha == M.WORKTREE and "worktree" or commit.sha:sub(1, 8),
                outdated = not present,
                texts = texts,
              }
            end
          end
        end
      end
    end
  end
  table.sort(order)
  for _, p in ipairs(order) do
    table.sort(by_path[p], function(a, b) return a.lnum < b.lnum end)
  end
  return { order = order, by_path = by_path }
end

-- ---------------------------------------------------------------------------
-- Build (pure projection): returns lines, row_map, highlights, comments.
-- ---------------------------------------------------------------------------

function Session:build()
  local lines = {}
  local row_map = {}
  local highlights = {}
  local function emit(text, target, hl)
    lines[#lines + 1] = text
    local row = #lines - 1
    row_map[row] = target
    if hl then highlights[#highlights + 1] = { row = row, hl = hl } end
    return row
  end

  -- A stored comment rendered as real, cursor-addressable buffer rows (multi-
  -- line text splits across rows). Every row carries the same comment identity
  -- so `dd`/`i` anywhere on it acts on the whole comment.
  local function emit_comment(text, sha, path, lnum)
    local ctarget = { comment = { sha = sha, path = path, lnum = lnum, text = text } }
    for i, part in ipairs(vim.split(text, "\n", { plain = true })) do
      emit((i == 1 and "    💬 " or "       ") .. part, ctarget, "GleanComment")
    end
  end

  local function emit_hunk(hunk, hi, target_base, resolve)
    local target = vim.tbl_extend("force", target_base, { hunk = hi })
    emit("--- " .. hunk.header, target, "GleanHunkHeader")
    for li, dl in ipairs(hunk.lines) do
      local marker = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
      local hl = dl.kind == "add" and "GleanAdd"
        or dl.kind == "del" and "GleanDel"
        or "GleanContext"
      local ad, kl, csha, cpath = nil, nil, nil, nil
      if dl.new_lnum then ad, kl, csha, cpath = resolve(dl.new_lnum) end
      emit(marker .. dl.text,
        vim.tbl_extend("force", target, { line = li }), hl)
      if ad then
        for _, t in ipairs(ad.comments_at(kl)) do
          emit_comment(t.text, csha, cpath, kl)
        end
      end
    end
  end

  local function emit_file_body(file, target_base, resolve, seen_ck)
    local seen_idx, unseen_idx = {}, {}
    for hi, hunk in ipairs(file.hunks) do
      if hunk_is_seen(hunk, resolve) then seen_idx[#seen_idx + 1] = hi
      else unseen_idx[#unseen_idx + 1] = hi end
    end
    if #seen_idx > 0 then
      local c = self.collapse[seen_ck]; if c == nil then c = true end
      local chev = c and CHEVRON_CLOSED or CHEVRON_OPEN
      emit(("  %s ✓ seen (%d hunks)"):format(chev, #seen_idx),
        vim.tbl_extend("force", target_base, { seen = true }), "GleanSeen")
      if not c then
        for _, hi in ipairs(seen_idx) do emit_hunk(file.hunks[hi], hi, target_base, resolve) end
      end
    end
    for _, hi in ipairs(unseen_idx) do emit_hunk(file.hunks[hi], hi, target_base, resolve) end
  end

  local mode_label = self.scope == "combined" and "combined" or "commit-by-commit"
  emit("── " .. mode_label .. " ──", {}, "GleanModeHeader")
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
            local resolve = function(ln) return adapter, ln, commit.sha, file.path end
            emit_file_body(file, { commit = ci, file = fi }, resolve,
              seen_key(commit.sha, file.path))
          end
        end
      end
    end
  else
    self.combined_files = self:compute_combined()
    for fi, cf in ipairs(self.combined_files) do
      local chevron = cf.raw.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
      local kind = cf.kind and (" [" .. cf.kind .. "]") or ""
      emit(chevron .. " " .. cf.path .. kind, { cfile = fi }, "GleanFileHeader")
      if not cf.raw.collapsed then
        local prov = self:provenance(cf.path)
        local resolve = function(ln)
          local p = prov[ln]
          if not p then return nil end
          return self:combined_adapter(p.sha, cf.path), p.orig_lnum, p.sha, cf.path
        end
        emit_file_body(cf, { cfile = fi }, resolve, cseen_key(cf.path))
      end
    end
  end

  local summary = self:collect_comments()
  if #summary.order > 0 then
    emit("", {})
    emit("══ comments ══", {}, "GleanModeHeader")
    for _, path in ipairs(summary.order) do
      emit(path, {}, "GleanFileHeader")
      for _, e in ipairs(summary.by_path[path]) do
        local loc = e.outdated
          and ("L%d (Outdated, from %s)"):format(e.lnum, e.short)
          or ("L%d"):format(e.lnum)
        emit(("  %s  %s"):format(loc, e.line), {}, e.outdated and "GleanSeen" or "GleanContext")
        for _, t in ipairs(e.texts) do
          for i, part in ipairs(vim.split(t.text, "\n", { plain = true })) do
            emit((i == 1 and "    💬 " or "       ") .. part, {}, "GleanComment")
          end
        end
      end
    end
  end

  return lines, row_map, highlights
end

function Session:render()
  local lines, row_map, highlights = self:build()
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
  if cur then
    local last = math.max(1, #lines)
    cur[1] = math.min(cur[1], last)
    pcall(api.nvim_win_set_cursor, win, cur)
  end
end

-- ---------------------------------------------------------------------------
-- Undo / redo — the buffer is a non-modifiable projection, so native undo does
-- not apply. Each user action (seen toggle, comment, collapse) is captured as a
-- small reversible action table; undo applies its reversal and moves it to the
-- redo stack, redo re-applies it. Actions are self-describing data, so the
-- stacks hold only the minimal delta, never a copy of the store.
--
--   seen:     { kind="seen", op="mark"|"unmark", groups={ {sha,path,lnums} } }
--   comment:  { kind="comment", sha, path, lnum, text }
--   collapse: { kind="collapse", key, value, prev, obj?, field? }
-- ---------------------------------------------------------------------------

-- Mark/unmark exactly the lines an action names; persist the touched shards.
-- combined_adapter resolves a (sha,path) to the right adapter in either scope.
function Session:apply_seen(groups, op)
  local touched = {}
  for _, g in ipairs(groups) do
    local ad = self:combined_adapter(g.sha, g.path)
    if op == "mark" then ad.mark(g.lnums) else ad.unmark(g.lnums) end
    touched[g.sha] = true
  end
  for sha in pairs(touched) do self.store:save_commit(sha) end
end

function Session:apply_comment(a, op)
  local ad = self:combined_adapter(a.sha, a.path)
  if op == "add" then
    ad.add_comment(a.lnum, a.text)
  elseif op == "remove" then
    ad.remove_comment(a.lnum, a.text)
  elseif op == "edit" then
    ad.remove_comment(a.lnum, a.old_text)
    ad.add_comment(a.lnum, a.text)
  elseif op == "unedit" then
    ad.remove_comment(a.lnum, a.text)
    ad.add_comment(a.lnum, a.old_text)
  end
  self.store:save_commit(a.sha)
end

-- Set a collapse key (nil clears it -> default) and mirror onto the model field
-- (commit/file/cf.raw .collapsed) when the action carries one.
function Session:apply_collapse_value(a, override, field_value)
  self.collapse[a.key] = override
  if a.obj then a.obj[a.field] = field_value end
end

function Session:apply_action(a)
  if a.kind == "seen" then
    self:apply_seen(a.groups, a.op)
  elseif a.kind == "comment" then
    self:apply_comment(a, a.op or "add")
  elseif a.kind == "collapse" then
    self:apply_collapse_value(a, a.value, a.field_value)
  end
end

function Session:reverse_action(a)
  if a.kind == "seen" then
    self:apply_seen(a.groups, a.op == "mark" and "unmark" or "mark")
  elseif a.kind == "comment" then
    local rev = { add = "remove", remove = "add", edit = "unedit" }
    self:apply_comment(a, rev[a.op or "add"])
  elseif a.kind == "collapse" then
    self:apply_collapse_value(a, a.prev, a.prev_field_value)
  end
end

-- Apply a fresh action, push it on the undo stack, and clear the redo stack.
function Session:perform(action)
  self:apply_action(action)
  self.undo_stack[#self.undo_stack + 1] = action
  self.redo_stack = {}
end

function Session:undo()
  local a = table.remove(self.undo_stack)
  if not a then
    vim.notify("glean: nothing to undo", vim.log.levels.INFO)
    return
  end
  self:reverse_action(a)
  self.redo_stack[#self.redo_stack + 1] = a
  self:render()
end

function Session:redo()
  local a = table.remove(self.redo_stack)
  if not a then
    vim.notify("glean: nothing to redo", vim.log.levels.INFO)
    return
  end
  self:apply_action(a)
  self.undo_stack[#self.undo_stack + 1] = a
  self:render()
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
  local action = self:collapse_action(target)
  if action then self:perform(action) end
  self:render()
end

-- Build the collapse action for `target`, or nil if the target is not
-- collapsible. A seen-section row toggles only its (default-collapsed) override
-- key; a file/commit/cfile row also mirrors the new state onto its model field
-- so the next render reflects it. prev/prev_field_value capture the exact prior
-- state so the action reverses cleanly.
function Session:collapse_action(target)
  -- key, obj/field (model mirror, optional), and the boolean the override
  -- toggles to (nil-as-collapsed default for seen sections).
  local key, obj, field, default_collapsed
  if self.scope == "commits" then
    local commit = self.commits[target.commit]
    if target.seen then
      key, default_collapsed = seen_key(commit.sha, commit.files[target.file].path), true
    elseif target.file then
      local file = commit.files[target.file]
      key, obj, field = file_key(commit.sha, file.path), file, "collapsed"
    elseif commit then
      key, obj, field = commit_key(commit.sha), commit, "collapsed"
    end
  else
    if target.seen then
      key, default_collapsed = cseen_key(self.combined_files[target.cfile].path), true
    elseif target.cfile then
      local cf = self.combined_files[target.cfile]
      key, obj, field = cfile_key(cf.path), cf.raw, "collapsed"
    end
  end
  if not key then return nil end
  local prev = self.collapse[key]
  local cur = obj and obj[field]
  if cur == nil then
    cur = prev; if cur == nil then cur = default_collapsed or false end
  end
  return {
    kind = "collapse",
    key = key,
    obj = obj,
    field = field,
    value = not cur,
    field_value = not cur,
    prev = prev,
    prev_field_value = cur,
  }
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
  if target.seen then return end
  -- Normalize the target to {sha, path, lnums} groups; combined_adapter resolves
  -- either scope's sha to the correct addressing adapter.
  local groups = {}
  if self.scope == "commits" then
    if not target.commit then return end
    for _, g in ipairs(self:target_groups(target)) do
      groups[#groups + 1] = { sha = g.commit.sha, path = g.file.path, lnums = g.lnums }
    end
  else
    if not target.cfile then return end
    local by_key = {}
    for _, t in ipairs(self:combined_tuples(target)) do
      local k = t.sha .. "\0" .. t.path
      local g = by_key[k]
      if not g then
        g = { sha = t.sha, path = t.path, lnums = {} }
        by_key[k] = g
        groups[#groups + 1] = g
      end
      g.lnums[#g.lnums + 1] = t.range[1]
    end
  end
  if #groups == 0 then return end
  -- Seen iff every addressed line is already seen -> we unmark; else we mark.
  local all_seen = true
  for _, g in ipairs(groups) do
    local ad = self:combined_adapter(g.sha, g.path)
    for _, l in ipairs(g.lnums) do
      if not ad.is_seen(l) then all_seen = false break end
    end
    if not all_seen then break end
  end
  local op = all_seen and "unmark" or "mark"
  -- Keep only the lines whose state actually flips, so the action reverses exactly.
  local changed = {}
  for _, g in ipairs(groups) do
    local ad = self:combined_adapter(g.sha, g.path)
    local lnums = {}
    for _, l in ipairs(g.lnums) do
      if (op == "mark") ~= ad.is_seen(l) then lnums[#lnums + 1] = l end
    end
    if #lnums > 0 then changed[#changed + 1] = { sha = g.sha, path = g.path, lnums = lnums } end
  end
  if #changed == 0 then return end
  self:perform({ kind = "seen", op = op, groups = changed })
  self:render()
  self:move_to_next_hunk(target)
end

-- After a hunk is toggled seen it relocates into the collapsed seen section, so
-- absolute cursor position is meaningless. Place the cursor on the header of the
-- next still-rendered hunk (document order) so review can continue.
function Session:move_to_next_hunk(from)
  if not (self.win and api.nvim_win_is_valid(self.win)) then return end
  if not from or not from.hunk then return end
  local function rank(t)
    if t.commit then return { t.commit, t.file or 0, t.hunk } end
    if t.cfile then return { t.cfile, t.hunk } end
    return nil
  end
  local function gt(a, b)
    for i = 1, #a do
      if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
  end
  local base = rank(from)
  if not base then return end
  local best_row, best_rank
  for r, t in pairs(self.row_map) do
    if t.hunk and not t.line and not t.seen then
      local tr = rank(t)
      if tr and gt(tr, base) and (not best_rank or gt(best_rank, tr)) then
        best_row, best_rank = r, tr
      end
    end
  end
  if best_row then pcall(api.nvim_win_set_cursor, self.win, { best_row + 1, 0 }) end
end

-- Mark a visual span of diff rows seen: translate each row's diff line to its
-- new_lnum, group by (commit, path), and store exactly those ranges (sub-hunk).
-- Deletion-only rows contribute no new-file line and are skipped.
function Session:mark_visual_range(srow, erow)
  if srow > erow then srow, erow = erow, srow end
  -- Collect normalized {sha, path, lnums} groups for the selected rows; the
  -- floating commit's content hashing is handled by combined_adapter.
  local groups, by_key = {}, {}
  local function add(sha, path, lnum)
    local k = sha .. "\0" .. path
    local g = by_key[k]
    if not g then
      g = { sha = sha, path = path, lnums = {} }
      by_key[k] = g
      groups[#groups + 1] = g
    end
    g.lnums[#g.lnums + 1] = lnum
  end
  for row = srow, erow do
    local target = self.row_map[row]
    if self.scope == "commits" then
      if target and target.commit and target.file and target.line then
        local commit = self.commits[target.commit]
        local file = commit.files[target.file]
        local dl = file.hunks[target.hunk].lines[target.line]
        if dl.new_lnum then add(commit.sha, file.path, dl.new_lnum) end
      end
    else
      if target and target.cfile and target.hunk and target.line then
        local cf = self.combined_files[target.cfile]
        local dl = cf.hunks[target.hunk].lines[target.line]
        local p = dl.new_lnum and self:provenance(cf.path)[dl.new_lnum]
        if p then add(p.sha, cf.path, p.orig_lnum) end
      end
    end
  end
  -- Mark only lines not already seen, so the action reverses exactly.
  local changed = {}
  for _, g in ipairs(groups) do
    local ad = self:combined_adapter(g.sha, g.path)
    local lnums = {}
    for _, l in ipairs(g.lnums) do
      if not ad.is_seen(l) then lnums[#lnums + 1] = l end
    end
    if #lnums > 0 then changed[#changed + 1] = { sha = g.sha, path = g.path, lnums = lnums } end
  end
  if #changed == 0 then return end
  self:perform({ kind = "seen", op = "mark", groups = changed })
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

-- Resolve a row to (adapter, new_lnum, sha, path): the addressing adapter to
-- author the comment through, the new-file line number to anchor it to, and the
-- shard id + path to persist/replay. Commit scope picks the owning commit's
-- adapter; combined scope routes to the provenance owner via a range adapter.
function Session:comment_anchor(row)
  local target = self.row_map[row]
  if not target or not target.line then return nil end
  if self.scope == "commits" then
    if not target.commit then return nil end
    local commit = self.commits[target.commit]
    local file = commit.files[target.file]
    local lnum = anchor_lnum(file.hunks[target.hunk], target.line)
    if not lnum then return nil end
    return self:adapter_for(commit, file.path), lnum, commit.sha, file.path
  else
    if not target.cfile then return nil end
    local cf = self.combined_files[target.cfile]
    local lnum = anchor_lnum(cf.hunks[target.hunk], target.line)
    local p = lnum and self:provenance(cf.path)[lnum]
    if not p then return nil end
    return self:combined_adapter(p.sha, cf.path), p.orig_lnum, p.sha, cf.path
  end
end

function Session:add_comment_at(row, text)
  if row == nil then row = self:cursor_row() end
  if not text or text == "" then return end
  local ad, lnum, sha, path = self:comment_anchor(row)
  if not ad then return end
  self:perform({ kind = "comment", sha = sha, path = path, lnum = lnum, text = text })
  self:render()
end

-- Delete a comment anchored to the cursor row's line. With one comment it is
-- removed directly; with several, the user picks which text to drop. The
-- removal is an undoable "comment" action (op = "remove"), so `u` restores it.
function Session:delete_comment_at(row)
  if row == nil then row = self:cursor_row() end
  local ad, lnum, sha, path = self:comment_anchor(row)
  if not ad then return end
  local list = ad.comments_at(lnum)
  if #list == 0 then
    vim.notify("glean: no comment on this line", vim.log.levels.INFO)
    return
  end
  local function drop(text)
    if not text then return end
    self:perform({ kind = "comment", op = "remove", sha = sha, path = path, lnum = lnum, text = text })
    self:render()
  end
  if #list == 1 then
    drop(list[1].text)
  else
    local choices = {}
    for _, c in ipairs(list) do choices[#choices + 1] = c.text end
    vim.ui.select(choices, { prompt = "glean: delete comment" }, drop)
  end
end

-- The comment identity under a cursor row, or nil. Comment rows are real,
-- cursor-addressable buffer lines (carrying { sha, path, lnum, text }) so `dd`
-- and `i` can act on the comment beneath the cursor directly.
function Session:comment_under(row)
  if row == nil then row = self:cursor_row() end
  local t = self.row_map[row]
  return t and t.comment or nil
end

-- Delete the comment under the cursor (undoable). No-op off a comment row.
function Session:delete_comment_under(row)
  local c = self:comment_under(row)
  if not c then return end
  self:perform({ kind = "comment", op = "remove", sha = c.sha, path = c.path, lnum = c.lnum, text = c.text })
  self:render()
end

-- Edit the comment under the cursor in the ephemeral split, replacing its text
-- (undoable). No-op off a comment row.
function Session:edit_comment_under(row)
  local c = self:comment_under(row)
  if not c then return end
  self:open_comment_editor(vim.split(c.text, "\n", { plain = true }), function(text)
    if text == c.text then return end
    self:perform({ kind = "comment", op = "edit", sha = c.sha, path = c.path, lnum = c.lnum, text = text, old_text = c.text })
    self:render()
  end)
end

-- Open an ephemeral, multi-line comment editor in a split above the glean
-- window, seeded with `initial` lines. `:w` submits the (trimmed-of-empty)
-- buffer text to `on_submit`; `q` or `<C-c>` cancels. The scratch buffer is
-- wiped on close so nothing persists outside the review store.
function Session:open_comment_editor(initial, on_submit)
  local ebuf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "acwrite", { buf = ebuf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = ebuf })
  api.nvim_set_option_value("filetype", "markdown", { buf = ebuf })
  pcall(api.nvim_buf_set_name, ebuf, "glean-comment://" .. ebuf)
  local seed = (initial and #initial > 0) and initial or { "" }
  api.nvim_buf_set_lines(ebuf, 0, -1, false, seed)

  if self.win and api.nvim_win_is_valid(self.win) then
    api.nvim_set_current_win(self.win)
  end
  vim.cmd("aboveleft split")
  local ewin = api.nvim_get_current_win()
  api.nvim_win_set_buf(ewin, ebuf)
  api.nvim_win_set_height(ewin, math.max(5, math.min(15, #seed + 1)))

  local done = false
  local function finish(submit)
    if done then return end
    done = true
    local text
    if submit then
      text = table.concat(api.nvim_buf_get_lines(ebuf, 0, -1, false), "\n")
    end
    if api.nvim_win_is_valid(ewin) then pcall(api.nvim_win_close, ewin, true) end
    if submit and text and text:match("%S") then on_submit(text) end
  end

  api.nvim_create_autocmd("BufWriteCmd", { buffer = ebuf, callback = function() finish(true) end })
  vim.keymap.set("n", "q", function() finish(false) end, { buffer = ebuf, nowait = true, silent = true })
  vim.keymap.set("n", "<C-c>", function() finish(false) end, { buffer = ebuf, silent = true })
  vim.cmd("startinsert")
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
    local row = session:cursor_row()
    if not session:comment_anchor(row) then
      vim.notify("glean: cannot comment here", vim.log.levels.INFO)
      return
    end
    session:open_comment_editor({}, function(text) session:add_comment_at(row, text) end)
  end)
  map("n", "i", function() session:edit_comment_under() end)
  map("n", "dd", function() session:delete_comment_under() end)
  map("n", "dc", function() session:delete_comment_at() end)
  map("n", "u", function() session:undo() end)
  map("n", "<C-r>", function() session:redo() end)
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
    undo_stack = {},
    redo_stack = {},
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
  api.nvim_set_hl(0, "GleanSeen", { link = "NonText", default = true })
  api.nvim_set_hl(0, "GleanComment", { link = "WarningMsg", default = true })
  api.nvim_set_hl(0, "GleanModeHeader", { link = "Title", default = true })
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
