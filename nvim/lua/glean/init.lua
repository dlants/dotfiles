-- glean: review the diff between two git refs in a single foldable buffer.
--
-- The model (FileEntries / Commits from glean.git, overlaid with the persisted
-- ReviewStore from glean.state) is the single source of truth; the buffer is a
-- pure projection of it. A parallel `row_map[row]` resolves any cursor row back
-- to its commit/file/hunk/line so actions can act on the semantic target.
--
-- Two scopes share one review store:
--   - "combined": the net diff base...target.
--   - "commits": every commit laid out flat, the natural place seen marks and
--     comments are *authored* against a stable (commit_sha, path, new_lnum).
--
-- Seen-ness has a single representation: a flat set of stable line-identities in
-- glean.state (committed add `(sha,lnum)`, committed del `(remover_sha,lnum)`,
-- and content-hashed worktree lines). The renderer's section placement, the
-- file/commit header glyphs, and the action layer all derive from the same
-- `Session:changed_lines`/`line_identity`/`line_seen`/`hunk_seen` resolver, so
-- "renders in the seen section" and "the action layer thinks it is seen" are
-- one computation by construction. Hunks are a pure display concern.
--
-- Collapse is ephemeral session view-state: it is initialized from seen status
-- when a scope is (re)built, then evolves independently and is never persisted.
--
-- Keymaps of note (`setup_keymaps`):
--   - normal `m` is overloaded: on a marker row/line (a collapsed seen sub-range
--     inside an unseen hunk, or any line of an expanded one) it unmarks that run;
--     on any other target it toggles the whole hunk/file/commit seen.
--   - visual `m` marks the selected lines seen; a partial selection renders as a
--     collapsed `✓ marked N lines` marker row (overlapping marks coalesce).
--   - `=` toggles collapse, including expanding/collapsing a marker row.
local git_mod = require("glean.git")
local state_mod = require("glean.state")
local provenance = require("glean.provenance")
local intraline = require("glean.intraline")
local M = {}
local api = vim.api

-- Reserved non-sha id for the synthetic "floating" commit that stands in for the
-- working tree on top of HEAD. Its reviewed units are content-addressed (hashes)
-- rather than line ranges, since uncommitted lines have no stable line numbers.
M.WORKTREE = "WORKTREE"
local NS = api.nvim_create_namespace("glean_hl")
local NS_INTRA = api.nvim_create_namespace("glean_intra_hl")
local NS_CURSOR = api.nvim_create_namespace("glean_cursor_hl")

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
local function unseen_key(sha, path) return "u:" .. sha .. "\0" .. path end
local function cunseen_key(path) return "cu:" .. path end

-- Content-addressed collapse key for a marker (a contiguous seen run inside an
-- unseen hunk). Keyed on the run's joined line texts so it stays stable when the
-- new-file line numbers shift (live/worktree) between renders.
local function marker_key(path, texts)
  return "mk:" .. path .. "\0" .. state_mod.line_hash(table.concat(texts, "\n"))
end
local function cmarker_key(path, texts)
  return "cmk:" .. path .. "\0" .. state_mod.line_hash(table.concat(texts, "\n"))
end

-- Build the review model for `base..target`: the net diff `files`, the ordered
-- `commits` (each with its own `commit_diff` files), and the `shas` to load from
-- the store. For a work-tree target the diff runs base->work tree and the
-- floating commit (tracked dirty edits + untracked files) is appended last.
-- Commit diffs are immutable per sha and only consulted in the commits scope, so
-- each commit's `files` is computed lazily on first access and memoized in a
-- session-lived, sha-keyed `cache`. A combined-scope review (the default) and
-- every live work-tree poll thus skip the per-commit `commit_diff` subprocess
-- entirely, and a scope toggle pays for it exactly once per sha.
local function lazy_commit_files(git, commit, cache)
  setmetatable(commit, { __index = function(t, k)
    if k ~= "files" then return nil end
    local f = cache[t.sha]
    if not f then f = git:commit_diff(t.sha) or {}; cache[t.sha] = f end
    rawset(t, "files", f)
    return f
  end })
end

local function build_model(git, base, target, commit_files)
  commit_files = commit_files or {}
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
    lazy_commit_files(git, c, commit_files)
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
    -- `git diff <base>` (the combined net diff) omits untracked files, so attach
    -- them to the combined file list too -- otherwise a brand-new file is visible
    -- (and markable) only in commit scope. Fresh entries keep the two scopes'
    -- ephemeral collapse state independent.
    for _, f in ipairs(git:untracked() or {}) do
      f.collapsed = false
      files[#files + 1] = f
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

-- The marker runs of a hunk: each maximal run of consecutive *changed* (add or
-- del) diff lines that `is_seen(dl)` reports seen. A context line or an unseen
-- changed line breaks the run, so a contiguous block of seen deletions collapses
-- into its own marker exactly like seen additions. Returns a list of descriptors
-- `{lo, hi_line, lnum_lo, lnum_hi, n, texts}` where `lo`/`hi_line` index into
-- `hunk.lines` (inclusive), `lnum_lo`/`lnum_hi` span the run's new-file lines
-- (nil across a pure-deletion run), and `texts` are the run's line texts (for
-- the content-addressed marker key).
local function hunk_marker_runs(hunk, is_seen)
  local runs = {}
  local cur = nil
  local function close()
    if cur then runs[#runs + 1] = cur end
    cur = nil
  end
  for i, dl in ipairs(hunk.lines) do
    local changed = dl.kind == "add" or dl.kind == "del"
    if changed and is_seen(dl) then
      if not cur then
        cur = { lo = i, hi_line = i, lnum_lo = dl.new_lnum, lnum_hi = dl.new_lnum, n = 1, texts = { dl.text } }
      else
        cur.hi_line = i
        cur.lnum_hi = dl.new_lnum or cur.lnum_hi
        cur.lnum_lo = cur.lnum_lo or dl.new_lnum
        cur.n = cur.n + 1
        cur.texts[#cur.texts + 1] = dl.text
      end
    else
      close()
    end
  end
  close()
  return runs
end

-- ---------------------------------------------------------------------------
-- Canonical seen resolver — the single representation everything folds over.
-- ---------------------------------------------------------------------------

-- The per-line owner closure for a commit-scope file: a changed line is owned
-- by its commit, keyed by new_lnum (adds) / old_lnum (dels). The floating
-- commit owns its lines as WORKTREE (content-addressed). `owner(dl) -> sha,lnum`.
function Session:commit_owner(commit)
  return function(dl)
    if commit.sha == M.WORKTREE then return M.WORKTREE end
    return commit.sha, dl.kind == "add" and dl.new_lnum or dl.old_lnum
  end
end

-- The per-line owner closure for a combined-scope file: an add/context line's
-- owner is its blame provenance (sha + orig_lnum). A deletion is owned by the
-- commit that removed it (resolved via `del_attribution`, in that commit's
-- immutable pre-image coords), or WORKTREE when the removal is uncommitted.
function Session:combined_owner(path)
  local prov = self:provenance(path)
  return function(dl)
    if dl.kind == "del" then
      local a = self:del_attribution(path)[dl.old_lnum]
      if a then return a.sha, a.lnum end
      return M.WORKTREE
    end
    if not dl.new_lnum then return nil end
    local p = prov[dl.new_lnum]
    -- An add line blame can't attribute (an untracked file has no blame at all,
    -- so its provenance map is empty) is uncommitted content in a work-tree
    -- review: route it to the content-addressed WORKTREE owner so it is markable.
    if not p then return self.worktree and M.WORKTREE or nil end
    return p.sha, p.orig_lnum
  end
end

-- Resolve combined-scope deletions to the immutable identity of the commit that
-- removed each line, numerically via `git blame --reverse` over base..target.
-- Reverse blame reports, for every base line, the *last* revision in which the
-- line still existed (`sha`) and its number there (`orig`); the line's deleter
-- is that revision's child in the ordered stack, and `orig` equals the deleter's
-- pre-image `old_lnum` -- the very `(sha, old_lnum)` commit scope records, so a
-- mark made in one view is seen in the other. The porcelain `final` field is the
-- base line number, i.e. the combined diff's del `old_lnum`, which keys the
-- returned map `old_lnum -> { sha, lnum }`. Lines that survive to the target, or
-- whose deleter is the floating work tree, are omitted -> content-hashed under
-- WORKTREE. Cached per path.
-- The parent->child map over the ordered commit stack (base first), used to name
-- the deleter of a line from the revision that last contained it. Depends only
-- on `self.base` and `self.commits`, so it is computed once per commit-set
-- generation (reset in `reload` only when the commit set changes), hoisting the
-- `rev_parse(base)` subprocess and stack walk out of the per-path loop.
function Session:del_child()
  if not self._del_child then
    local child, prev = {}, self.git:rev_parse(self.base) or self.base
    for _, c in ipairs(self.commits) do
      if c.sha ~= M.WORKTREE then child[prev] = c.sha; prev = c.sha end
    end
    self._del_child = child
  end
  return self._del_child
end

function Session:del_attribution(path)
  self._del_attr = self._del_attr or {}
  if self._del_attr[path] == nil then
    local map = {}
    local end_rev = self.target ~= M.WORKTREE and self.target or "HEAD"
    local child = self:del_child()
    local out = self.git:reverse_blame(self.base, end_rev, path)
    for final, p in pairs((out and provenance.parse_blame(out)) or {}) do
      local deleter = child[p.sha]
      if deleter then map[final] = { sha = deleter, lnum = p.orig_lnum } end
    end
    self._del_attr[path] = map
  end
  return self._del_attr[path]
end

-- The stable seen-identity of one changed diff line, or nil for a context line
-- or a line with no in-range owner. A WORKTREE-owned line is content-addressed;
-- a committed add line is (sha, new_lnum); a committed del line is (sha, lnum).
function Session:line_identity(dl, path, owner)
  if dl.kind ~= "add" and dl.kind ~= "del" then return nil end
  local sha, lnum = owner(dl)
  if not sha then return nil end
  if sha == M.WORKTREE then return state_mod.wt_identity(path, dl.text) end
  if dl.kind == "add" then return state_mod.add_identity(sha, path, lnum) end
  return state_mod.del_identity(sha, path, lnum)
end

-- The seen-identities of a hunk's changed (add/del) lines — the one place that
-- defines "which lines matter". Context lines and unowned lines are excluded.
function Session:changed_lines(hunk, path, owner)
  local ids = {}
  for _, dl in ipairs(hunk.lines) do
    local id = self:line_identity(dl, path, owner)
    if id then ids[#ids + 1] = id end
  end
  return ids
end

-- Is a single line identity in the seen set?
function Session:line_seen(id)
  return self.store:is_seen(id)
end

-- A hunk is seen iff it has at least one changed line and every changed line's
-- identity is seen. This is the single predicate the renderer and the rollups
-- share, so placement and the header glyphs agree by construction.
function Session:hunk_seen(hunk, path, owner)
  local ids = self:changed_lines(hunk, path, owner)
  if #ids == 0 then return false end
  return self.store:all_seen(ids)
end

-- Is a file fully seen? (every hunk's changed lines seen)
function Session:file_seen(commit, file)
  local owner = self:commit_owner(commit)
  for _, hunk in ipairs(file.hunks) do
    if not self:hunk_seen(hunk, file.path, owner) then return false end
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

-- Flatten a file's hunks to its ordered diff-line list. This is the resolution
-- space comment `content[]` is matched against: only literal diff-line rows
-- (context/add/del), never decoration rows (headers, comments, summaries).
local function flatten_diff_lines(file)
  local out = {}
  for _, hunk in ipairs(file.hunks) do
    for _, dl in ipairs(hunk.lines) do
      out[#out + 1] = dl
    end
  end
  return out
end

-- The flattened diff-line ordinal of a (hunk, line) target within its file.
local function target_ordinal(file, target)
  local ord = 0
  for hi = 1, target.hunk - 1 do
    ord = ord + #file.hunks[hi].lines
  end
  return ord + target.line
end

-- The diff file a target row belongs to (commit scope: its commit's file;
-- combined scope: the cfile), or nil for non-diff rows.
function Session:row_file(target)
  if not target then return nil end
  if self.scope == "commits" then
    if not target.commit or not target.file then return nil end
    return self.commits[target.commit].files[target.file]
  end
  if not target.cfile then return nil end
  return self.combined_files[target.cfile]
end

-- Every diff file currently displayed, in document order.
function Session:displayed_files()
  local fs = {}
  if self.scope == "commits" then
    for _, c in ipairs(self.commits) do
      for _, f in ipairs(c.files) do fs[#fs + 1] = f end
    end
  else
    for _, cf in ipairs(self:compute_combined()) do fs[#fs + 1] = cf end
  end
  return fs
end

-- Re-anchor a file's comments against its current diff-line texts: map the
-- flattened ordinal each comment resolves to (its content match, or its stored
-- `anchor` when the content is gone) to the list of comments shown there. A
-- comment whose anchor falls outside the file is dropped from the inline view
-- (it still appears in the summary).
function Session:resolve_comments(file)
  local flat = flatten_diff_lines(file)
  local texts = {}
  for i, dl in ipairs(flat) do texts[i] = dl.text end
  local by_ord = {}
  for _, rec in ipairs(self.store:comments_for(file.path)) do
    local start = state_mod.resolve(rec.content, rec.anchor, texts)
    local ord = start or rec.anchor
    if ord and ord >= 1 and ord <= #flat then
      by_ord[ord] = by_ord[ord] or {}
      by_ord[ord][#by_ord[ord] + 1] = {
        path = file.path,
        anchor = rec.anchor,
        content = rec.content,
        text = rec.text,
        outdated = start == nil,
      }
    end
  end
  return by_ord
end

-- Gather every stored comment for the displayed file paths, re-anchored by
-- content. Each record { anchor, content, text } is resolved against the file's
-- flattened diff-line texts: a match yields the matched line's number, a miss is
-- flagged `outdated` and anchored to its stored ordinal. Comments are global per
-- path, so a path appearing in several commits is de-duplicated (a resolved
-- match wins over an outdated one). Returns { order = {paths}, by_path }.
function Session:collect_comments()
  local best = {}
  for _, file in ipairs(self:displayed_files()) do
    local flat = flatten_diff_lines(file)
    local texts = {}
    for i, dl in ipairs(flat) do texts[i] = dl.text end
    for _, rec in ipairs(self.store:comments_for(file.path)) do
      local start = state_mod.resolve(rec.content, rec.anchor, texts)
      local dl = flat[start or rec.anchor]
      local entry = {
        anchor = rec.anchor,
        line = rec.content[1] or "",
        lnum = dl and (dl.new_lnum or dl.old_lnum),
        outdated = start == nil,
        text = rec.text,
      }
      local rkey = tostring(rec.anchor) .. "\0"
        .. table.concat(rec.content, "\n") .. "\0" .. rec.text
      best[file.path] = best[file.path] or {}
      local prev = best[file.path][rkey]
      if not prev or (prev.outdated and not entry.outdated) then
        best[file.path][rkey] = entry
      end
    end
  end
  local order = {}
  local by_path = {}
  for path, recs in pairs(best) do
    order[#order + 1] = path
    local list = {}
    for _, e in pairs(recs) do list[#list + 1] = e end
    table.sort(list, function(a, b) return (a.anchor or 0) < (b.anchor or 0) end)
    by_path[path] = list
  end
  table.sort(order)
  return { order = order, by_path = by_path }
end

-- ---------------------------------------------------------------------------
-- Ancestry classification (pure): for each row, the ordered stack of enclosing
-- header rows (commit, file, section, hunk). Drives the sticky-header float.
-- Walks rows top-to-bottom carrying a running ancestry; a shallower header
-- clears deeper levels. Headers are identified purely from row_map target shape:
--   commit header  → { commit } (no file/cfile/sec/hunk)
--   section header → { ..., seen|unseen }
--   file header    → { file|cfile } (no hunk/line)
--   hunk header    → { ..., hunk } (no line, no marker)
function M.compute_ancestry(row_map, n)
  local ancestry = {}
  local commit_row, file_row, sec_row, hunk_row
  for row = 0, n - 1 do
    local t = row_map[row]
    if t then
      if t.commit and not t.file and not t.cfile and not t.sec and not t.hunk then
        commit_row, file_row, sec_row, hunk_row = row, nil, nil, nil
      elseif t.seen or t.unseen then
        sec_row, hunk_row = row, nil
      elseif (t.file or t.cfile) and not t.hunk and not t.line then
        file_row, sec_row, hunk_row = row, nil, nil
      elseif t.hunk and t.line == nil and t.marker == nil then
        hunk_row = row
      end
    end
    ancestry[row] = {
      commit_row = commit_row,
      file_row = file_row,
      sec_row = sec_row,
      hunk_row = hunk_row,
    }
  end
  return ancestry
end

-- Pinned-set selection (pure): given an ancestry table and the top visible row
-- w0, return the ordered list of header rows to pin, [commit, file, sec, hunk],
-- filtered to rows strictly above w0 (a still-visible header isn't duplicated).
-- An empty list means no float should be shown.
function M.compute_pinned(ancestry, w0)
  local pinned = {}
  local a = ancestry[w0]
  if not a then
    return pinned
  end
  for _, row in ipairs({ a.commit_row or false, a.file_row or false,
    a.sec_row or false, a.hunk_row or false }) do
    if row and row < w0 then
      pinned[#pinned + 1] = row
    end
  end
  return pinned
end

-- ---------------------------------------------------------------------------
-- Build (pure projection): returns lines, row_map, highlights, comments.
-- ---------------------------------------------------------------------------

function Session:build()
  local lines = {}
  local row_map = {}
  local highlights = {}
  local intra_blocks = {}
  local function emit(text, target, hl)
    lines[#lines + 1] = text
    local row = #lines - 1
    row_map[row] = target
    if hl then highlights[#highlights + 1] = { row = row, hl = hl } end
    return row
  end

  -- A stored comment rendered as real, cursor-addressable buffer rows (multi-
  -- line text splits across rows). Every row carries the same comment identity
  -- (path + record) so `dd`/`i`/`dc` anywhere on it acts on the whole comment.
  local function emit_comment(c)
    local ctarget = { comment = c }
    for i, part in ipairs(vim.split(c.text, "\n", { plain = true })) do
      emit((i == 1 and "    💬 " or "       ") .. part, ctarget, "GleanComment")
    end
  end

  local function emit_hunk(hunk, hi, target_base, owner, base_ord, comments_by_ord, sec, path)
    local target = vim.tbl_extend("force", target_base, { hunk = hi, sec = sec })
    emit("--- " .. hunk.header, target, "GleanHunkHeader")
    -- Markers are an unseen-hunk affordance only: a hunk in the seen section is
    -- fully seen and always renders whole, never collapsing sub-ranges. A run is
    -- any contiguous block of seen changed lines (adds or dels), via the shared
    -- line-identity predicate.
    local seen_line = function(dl)
      local id = self:line_identity(dl, path, owner)
      return id ~= nil and self.store:is_seen(id)
    end
    local runs = sec == "seen" and {} or hunk_marker_runs(hunk, seen_line)
    local run_at = {}
    for _, run in ipairs(runs) do run_at[run.lo] = run end
    local dels, adds = {}, {}
    local li = 1
    while li <= #hunk.lines do
      local run = run_at[li]
      if run then
        local mk = (self.scope == "combined")
          and cmarker_key(path, run.texts) or marker_key(path, run.texts)
        local collapsed = self.collapse[mk]
        if collapsed == nil then collapsed = true end
        local mtarget = vim.tbl_extend("force", target, { marker = {
          lo = run.lo, hi_line = run.hi_line,
          lnum_lo = run.lnum_lo, lnum_hi = run.lnum_hi,
          n = run.n, texts = run.texts,
        } })
        local label = ("marked %d line%s"):format(run.n, run.n == 1 and "" or "s")
        if collapsed then
          emit("  ✓ " .. label, mtarget, "GleanSeen")
        else
          emit("  " .. CHEVRON_OPEN .. " ✓ " .. label, mtarget, "GleanSeen")
          for ri = run.lo, run.hi_line do
            local dl = hunk.lines[ri]
            local m = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
            emit(m .. dl.text,
              vim.tbl_extend("force", mtarget, { line = ri }), "GleanSeen")
            for _, c in ipairs(comments_by_ord[base_ord + ri] or {}) do
              emit_comment(c)
            end
          end
        end
        li = run.hi_line + 1
      else
        local dl = hunk.lines[li]
        local m = dl.kind == "add" and "+" or dl.kind == "del" and "-" or " "
        local hl = dl.kind == "add" and "GleanAdd"
          or dl.kind == "del" and "GleanDel"
          or "GleanContext"
        local row = emit(m .. dl.text,
          vim.tbl_extend("force", target, { line = li }), hl)
        if dl.kind == "del" then
          dels[#dels + 1] = { row = row, text = dl.text }
        elseif dl.kind == "add" then
          adds[#adds + 1] = { row = row, text = dl.text }
        end
        for _, c in ipairs(comments_by_ord[base_ord + li] or {}) do
          emit_comment(c)
        end
        li = li + 1
      end
    end
    -- Defer the expensive intra-line pairing/alignment to the async phase: emit
    -- only the raw del/add rows+texts per hunk. Phase 1's whole-line highlight
    -- stands until the refinement upgrades it.
    if #dels > 0 and #adds > 0 then
      intra_blocks[#intra_blocks + 1] = { dels = dels, adds = adds }
    end
  end

  local function emit_file_body(file, target_base, owner, seen_ck, comments_by_ord, unseen_ck)
    local seen_idx, unseen_idx = {}, {}
    local base_ord = {}
    local acc = 0
    for hi, hunk in ipairs(file.hunks) do
      base_ord[hi] = acc
      acc = acc + #hunk.lines
      if self:hunk_seen(hunk, file.path, owner) then seen_idx[#seen_idx + 1] = hi
      else unseen_idx[#unseen_idx + 1] = hi end
    end
    if #seen_idx > 0 then
      local c = self.collapse[seen_ck]; if c == nil then c = true end
      local chev = c and CHEVRON_CLOSED or CHEVRON_OPEN
      emit(("  %s ✓ seen (%d hunks)"):format(chev, #seen_idx),
        vim.tbl_extend("force", target_base, { seen = true }), "GleanSeen")
      if not c then
        for _, hi in ipairs(seen_idx) do
          emit_hunk(file.hunks[hi], hi, target_base, owner, base_ord[hi], comments_by_ord, "seen", file.path)
        end
      end
    end
    if #unseen_idx > 0 then
      local c = self.collapse[unseen_ck]; if c == nil then c = false end
      local chev = c and CHEVRON_CLOSED or CHEVRON_OPEN
      emit(("  %s ● unseen (%d hunks)"):format(chev, #unseen_idx),
        vim.tbl_extend("force", target_base, { unseen = true }), "GleanFileHeader")
      if not c then
        for _, hi in ipairs(unseen_idx) do
          emit_hunk(file.hunks[hi], hi, target_base, owner, base_ord[hi], comments_by_ord, "unseen", file.path)
        end
      end
    end
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
            emit_file_body(file, { commit = ci, file = fi },
              self:commit_owner(commit),
              seen_key(commit.sha, file.path), self:resolve_comments(file),
              unseen_key(commit.sha, file.path))
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
        emit_file_body(cf, { cfile = fi }, self:combined_owner(cf.path),
          cseen_key(cf.path), self:resolve_comments(cf), cunseen_key(cf.path))
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
        local loc = e.outdated and "(Outdated)"
          or (e.lnum and ("L%d"):format(e.lnum) or "L?")
        emit(("  %s  %s"):format(loc, e.line), {}, e.outdated and "GleanSeen" or "GleanContext")
        for i, part in ipairs(vim.split(e.text, "\n", { plain = true })) do
          emit((i == 1 and "    💬 " or "       ") .. part, {}, "GleanComment")
        end
      end
    end
  end

  return lines, row_map, highlights, intra_blocks
end

function Session:render()
  local lines, row_map, highlights, intra_work = self:build()
  self.row_map = row_map
  self.ancestry = M.compute_ancestry(row_map, #lines)
  self.row_hl = {}
  for _, hl in ipairs(highlights) do
    self.row_hl[hl.row] = hl.hl
  end
  local win = self.win
  local cur
  if win and api.nvim_win_is_valid(win) then
    cur = api.nvim_win_get_cursor(win)
  end
  api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = self.buf })
  api.nvim_buf_clear_namespace(self.buf, NS, 0, -1)
  -- Per-row full-line extmark ids for add/del lines, so phase-2 can downgrade an
  -- aligned line's background to foreground-only (the emphasis layer then paints
  -- just the changed spans with the diff background).
  self._line_marks = {}
  for _, hl in ipairs(highlights) do
    local id = api.nvim_buf_set_extmark(self.buf, NS, hl.row, 0, {
      end_row = hl.row + 1,
      end_col = 0,
      hl_group = hl.hl,
      hl_eol = true,
    })
    if hl.hl == "GleanAdd" or hl.hl == "GleanDel" then
      self._line_marks[hl.row] = { id = id, base = hl.hl }
    end
  end
  self:apply_intraline(intra_work)
  if cur then
    local last = math.max(1, #lines)
    cur[1] = math.min(cur[1], last)
    pcall(api.nvim_win_set_cursor, win, cur)
  end
  self:highlight_cursor_hunk()
end

-- Phase 2 of rendering: intra-line (word-level) emphasis, computed off the
-- synchronous render path. `build()` emits only raw del/add blocks; the
-- expensive pairing + token alignment (intraline.refine) runs here, chunked via
-- vim.schedule, so the buffer first shows whole-line add/del highlighting and
-- upgrades to changed-span emphasis as each block is refined.
--
-- Refinement is content-addressable (independent of buffer rows), so results are
-- cached by the block's del/add text in `self._intra_cache` and reused across
-- re-renders (mark/collapse) and reloads (save) -- an unchanged hunk is refined
-- exactly once. The caller maps the cached di/ai indices back to current rows.
--
-- Each render bumps `self._intra_gen` and clears NS_INTRA synchronously; every
-- chunk re-checks (via intraline.is_current) that its captured generation still
-- matches and the buffer is still valid, so a re-render/reload mid-flight
-- abandons stale work. INTRA_BUDGET bounds the del+add lines refined per tick.
local INTRA_BUDGET = 40
function Session:apply_intraline(blocks)
  self._intra_gen = (self._intra_gen or 0) + 1
  local gen = self._intra_gen
  api.nvim_buf_clear_namespace(self.buf, NS_INTRA, 0, -1)
  if #blocks == 0 then
    return
  end
  self._intra_cache = self._intra_cache or {}
  -- Downgrade an aligned line's full-line background (placed in phase 1) to a
  -- foreground-only color, by re-setting its extmark in place. The changed spans
  -- then carry the diff background, so emphasis reads as "background = changed".
  local TEXT_HL = { GleanAdd = "GleanAddText", GleanDel = "GleanDelText" }
  local function downgrade(row)
    local mark = self._line_marks and self._line_marks[row]
    if not mark then
      return
    end
    api.nvim_buf_set_extmark(self.buf, NS, row, 0, {
      id = mark.id,
      end_row = row + 1,
      end_col = 0,
      hl_group = TEXT_HL[mark.base],
      hl_eol = true,
    })
  end
  local function paint(row, segs, hl)
    for _, seg in ipairs(segs) do
      api.nvim_buf_set_extmark(self.buf, NS_INTRA, row, 1 + seg.start_col, {
        end_row = row,
        end_col = 1 + seg.end_col,
        hl_group = hl,
        priority = 4200,
      })
    end
  end
  local bi = 1
  local function step()
    if not intraline.is_current(gen, self._intra_gen, api.nvim_buf_is_valid(self.buf)) then
      return
    end
    local budget = 0
    while bi <= #blocks and budget < INTRA_BUDGET do
      local block = blocks[bi]
      bi = bi + 1
      budget = budget + #block.dels + #block.adds
      local del_texts, add_texts = {}, {}
      for _, d in ipairs(block.dels) do del_texts[#del_texts + 1] = d.text end
      for _, a in ipairs(block.adds) do add_texts[#add_texts + 1] = a.text end
      -- Content-addressed cache key: the del/add line texts fully determine the
      -- refinement, so an unchanged hunk hits the cache across re-renders/reloads.
      local key = table.concat(del_texts, "\n") .. "\0\0" .. table.concat(add_texts, "\n")
      local refined = self._intra_cache[key]
      if not refined then
        refined = intraline.refine(del_texts, add_texts)
        self._intra_cache[key] = refined
      end
      -- Map the cached di/ai indices back to this render's rows. Only drop a
      -- side's full-line background when it has changed spans to paint; an empty
      -- seg list means that line is unchanged and keeps its full-line highlight.
      -- A pair means we resolved what changed, so both lines drop their
      -- full-line background and read as text; the changed spans (which may be
      -- on only one side, e.g. a pure in-line insertion) then carry the diff
      -- background. Downgrading unconditionally keeps the unchanged side from
      -- staying solid -- the "we gave up" look -- when only its mate changed.
      for _, r in ipairs(refined) do
        downgrade(block.dels[r.di].row)
        downgrade(block.adds[r.ai].row)
        paint(block.dels[r.di].row, r.a_segs, "GleanDelEmph")
        paint(block.adds[r.ai].row, r.b_segs, "GleanAddEmph")
      end
    end
    if bi <= #blocks then
      vim.schedule(step)
    end
  end
  vim.schedule(step)
end

-- Mark every row of the hunk under the cursor with a `▌` bar in the sign column,
-- so the active hunk's extent reads as a single contiguous block in the gutter.
-- Cleared and reapplied on each move.
function Session:highlight_cursor_hunk()
  if not (self.buf and api.nvim_buf_is_valid(self.buf)) then return end
  api.nvim_buf_clear_namespace(self.buf, NS_CURSOR, 0, -1)
  if not (self.win and api.nvim_win_is_valid(self.win)) then return end
  api.nvim_set_option_value("signcolumn", "yes:1", { win = self.win })
  local t = self.row_map[self:cursor_row()]
  if not (t and t.hunk) then return end
  local function same(o)
    return o and o.hunk == t.hunk and o.commit == t.commit
      and o.file == t.file and o.cfile == t.cfile
  end
  for r, o in pairs(self.row_map) do
    if same(o) then
      api.nvim_buf_set_extmark(self.buf, NS_CURSOR, r, 0, {
        sign_text = "▌",
        sign_hl_group = "GleanCurrentHunk",
        priority = 100,
      })
    end
  end
end

-- ---------------------------------------------------------------------------
-- The inclusive [lo, hi] row span of the hunk under `row` (the same set of rows
-- highlight_cursor_hunk paints), or nil when the row is not inside a hunk.
function Session:hunk_range(row)
  local t = self.row_map[row]
  if not (t and t.hunk) then return end
  local function same(o)
    return o and o.hunk == t.hunk and o.commit == t.commit
      and o.file == t.file and o.cfile == t.cfile
  end
  local lo, hi
  for r, o in pairs(self.row_map) do
    if same(o) then
      if not lo or r < lo then lo = r end
      if not hi or r > hi then hi = r end
    end
  end
  return lo, hi
end

-- Linewise-select the hunk under the cursor. Wired to the `ac` text object, so
-- it composes in both visual (`vac`) and operator-pending (`dac`, etc.) modes.
function Session:select_hunk_textobj()
  local lo, hi = self:hunk_range(self:cursor_row())
  if not (lo and self.win and api.nvim_win_is_valid(self.win)) then return end
  -- Drop any in-progress visual selection first; otherwise `normal! V` keeps the
  -- original anchor and the range only extends one way from the cursor.
  if api.nvim_get_mode().mode:match("[vV\22]") then
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  end
  api.nvim_win_set_cursor(self.win, { lo + 1, 0 })
  vim.cmd("normal! V")
  api.nvim_win_set_cursor(self.win, { hi + 1, 0 })
end
-- Undo / redo — the buffer is a non-modifiable projection, so native undo does
-- not apply. Each user action (seen toggle, comment, collapse) is captured as a
-- small reversible action table; undo applies its reversal and moves it to the
-- redo stack, redo re-applies it. Actions are self-describing data, so the
-- stacks hold only the minimal delta, never a copy of the store.
--
--   seen:     { kind="seen", op="mark"|"unmark", groups={ {sha,path,lnums} } }
--   comment:  { kind="comment", op, path, record={anchor,content,text}, old_record? }
--   collapse: { kind="collapse", key, value, prev, obj?, field? }
-- ---------------------------------------------------------------------------

-- Mark/unmark exactly the line-identities an action names; persist the touched
-- shards. Every seen action (commit/combined toggle, visual span, marker run)
-- now carries a flat list of seen-`ids`, so this is a single fold over the
-- unified identity store with no scope- or owner-specific branching.
function Session:apply_seen(a, op)
  if op == "mark" then self.store:mark(a.ids) else self.store:unmark(a.ids) end
  local touched = {}
  for _, id in ipairs(a.ids) do
    touched[id.kind == "wt" and state_mod.COMMENTS_ID or id.sha] = true
  end
  for sha in pairs(touched) do self.store:save_commit(sha) end
end

function Session:apply_comment(a, op)
  if op == "add" then
    self.store:add_comment_record(a.path, a.record)
  elseif op == "remove" then
    self.store:remove_comment_record(a.path, a.record)
  elseif op == "edit" then
    self.store:remove_comment_record(a.path, a.old_record)
    self.store:add_comment_record(a.path, a.record)
  elseif op == "unedit" then
    self.store:remove_comment_record(a.path, a.record)
    self.store:add_comment_record(a.path, a.old_record)
  end
  self.store:save_commit(state_mod.COMMENTS_ID)
end

-- Set a collapse key (nil clears it -> default) and mirror onto the model field
-- (commit/file/cf.raw .collapsed) when the action carries one.
function Session:apply_collapse_value(a, override, field_value)
  self.collapse[a.key] = override
  if a.obj then a.obj[a.field] = field_value end
end

function Session:apply_action(a)
  if a.kind == "seen" then
    self:apply_seen(a, a.op)
  elseif a.kind == "comment" then
    self:apply_comment(a, a.op or "add")
  elseif a.kind == "collapse" then
    self:apply_collapse_value(a, a.value, a.field_value)
  end
end

function Session:reverse_action(a)
  if a.kind == "seen" then
    self:apply_seen(a, a.op == "mark" and "unmark" or "mark")
  elseif a.kind == "comment" then
    local rev = { add = "remove", remove = "add", edit = "unedit" }
    self:apply_comment(a, rev[a.op or "add"])
  elseif a.kind == "collapse" then
    self:apply_collapse_value(a, a.prev, a.prev_field_value)
  end
end

-- Apply a fresh action, push it on the undo stack, and clear the redo stack.
function Session:perform(action)
  action.cursor = self:cursor_row()
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
  self:restore_cursor(a.cursor)
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

function Session:restore_cursor(row)
  if not (row and self.win and api.nvim_win_is_valid(self.win)) then return end
  row = math.max(0, math.min(row, api.nvim_buf_line_count(self.buf) - 1))
  pcall(api.nvim_win_set_cursor, self.win, { row + 1, 0 })
end

-- The seen/unseen section a target belongs to, or nil. Section headers carry
-- `seen`/`unseen`; hunk and diff-line rows carry `sec`. Identity is the owning
-- file (commit+file in commit scope, cfile in combined scope).
function Session:section_of(target)
  local kind
  if target.seen then kind = "seen"
  elseif target.unseen then kind = "unseen"
  elseif target.sec then kind = target.sec
  else return nil end
  if target.commit then
    return { commit = target.commit, file = target.file, kind = kind }
  elseif target.cfile then
    return { cfile = target.cfile, kind = kind }
  end
  return nil
end

function Session:section_key(sec)
  if sec.commit then
    local commit = self.commits[sec.commit]
    local path = commit.files[sec.file].path
    return sec.kind == "seen" and seen_key(commit.sha, path) or unseen_key(commit.sha, path)
  end
  local path = self.combined_files[sec.cfile].path
  return sec.kind == "seen" and cseen_key(path) or cunseen_key(path)
end

local function same_section(a, b)
  return a and b and a.kind == b.kind and a.commit == b.commit
    and a.file == b.file and a.cfile == b.cfile
end

-- The buffer row of a section's header (the seen/unseen summary line), or nil.
function Session:section_header_row(sec)
  for r, t in pairs(self.row_map) do
    if (t.seen or t.unseen) and same_section(self:section_of(t), sec) then
      return r
    end
  end
  return nil
end

-- A section header (default-collapsed for seen, default-expanded for unseen)
-- toggles only its override key. Returns the action and whether it collapses.
function Session:section_action(sec)
  local key = self:section_key(sec)
  local prev = self.collapse[key]
  local cur = prev
  if cur == nil then cur = (sec.kind == "seen") end
  return {
    kind = "collapse",
    key = key,
    value = not cur,
    field_value = not cur,
    prev = prev,
    prev_field_value = nil,
  }, (not cur)
end

function Session:toggle_collapse(row)
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  if not target then return end

  -- A marker row carries `sec` too, but it toggles only its own collapse key,
  -- not the whole section, so handle it before the section branch.
  if target.marker then
    local action = self:collapse_action(target)
    if action then self:perform(action) end
    self:render()
    return
  end

  -- Section rows (seen/unseen headers, hunks, diff lines) collapse just their
  -- section, leaving the file header in place. Collapsing parks the cursor on
  -- the header; expanding restores the row the user left off on inside it.
  local sec = self:section_of(target)
  if sec then
    self.section_offsets = self.section_offsets or {}
    local action, collapsing = self:section_action(sec)
    local key = self:section_key(sec)
    if collapsing then
      local hrow = self:section_header_row(sec) or row
      self.section_offsets[key] = row - hrow
    end
    self:perform(action)
    self:render()
    local hrow = self:section_header_row(sec)
    if hrow then
      local dst = hrow
      if not collapsing then dst = hrow + (self.section_offsets[key] or 0) end
      dst = math.max(0, math.min(dst, api.nvim_buf_line_count(self.buf) - 1))
      pcall(api.nvim_win_set_cursor, self.win, { dst + 1, 0 })
    end
    return
  end

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
  -- A marker row toggles only its content-addressed marker key (default
  -- collapsed), with no model mirror -- like the seen-section override.
  if target.marker then
    local path
    if self.scope == "commits" then
      path = self.commits[target.commit].files[target.file].path
    else
      path = self.combined_files[target.cfile].path
    end
    key = (self.scope == "combined")
      and cmarker_key(path, target.marker.texts)
      or marker_key(path, target.marker.texts)
    default_collapsed = true
  elseif self.scope == "commits" then
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

-- Stable identity of a hunk target, surviving its relocation into the seen
-- section (the hunk index into file.hunks does not change when marked seen).
local function hunk_key(t)
  if not t then return nil end
  if t.commit then return ("c:%d:%d:%d"):format(t.commit, t.file or 0, t.hunk or 0) end
  if t.cfile then return ("f:%d:%d"):format(t.cfile, t.hunk or 0) end
  return nil
end

-- Whether two hunk targets belong to the same displayed file (commit+file in
-- the commits scope, cfile in combined).
local function same_file(a, b)
  if not (a and b) then return false end
  if a.commit then return a.commit == b.commit and a.file == b.file end
  if a.cfile then return a.cfile == b.cfile end
  return false
end

-- The seen-identities a target row addresses: every changed (add/del) line of
-- the commit (commit header), file (file header), or hunk it covers. Context
-- and unowned lines carry no identity and are excluded, so marking a unit is
-- defined purely as add/remove over these identities.
function Session:target_identities(target)
  local out = {}
  local function gather(hunks, path, owner)
    for _, h in ipairs(hunks) do
      for _, id in ipairs(self:changed_lines(h, path, owner)) do
        out[#out + 1] = id
      end
    end
  end
  if self.scope == "commits" then
    local commit = self.commits[target.commit]
    if not commit then return out end
    local owner = self:commit_owner(commit)
    local files = target.file and { commit.files[target.file] } or commit.files
    for _, file in ipairs(files) do
      gather(target.hunk and { file.hunks[target.hunk] } or file.hunks, file.path, owner)
    end
  else
    local cf = self.combined_files and self.combined_files[target.cfile]
    if not cf then return out end
    local owner = self:combined_owner(cf.path)
    gather(target.hunk and { cf.hunks[target.hunk] } or cf.hunks, cf.path, owner)
  end
  return out
end

-- The seen collapse-section key an identity lands in: per (commit, path) in
-- commit scope, per path in combined scope -- matching emit_file_body's seen
-- section keys so marking re-collapses exactly that destination section.
function Session:seen_collapse_key(id)
  if self.scope == "commits" then
    return seen_key(id.kind == "wt" and M.WORKTREE or id.sha, id.path)
  end
  return cseen_key(id.path)
end

-- The single identity of one literal diff-line row, or nil for a non-line row or
-- a context/unowned line. Used by the visual-range and marker actions, which act
-- on individual rows rather than whole hunks.
function Session:row_identity(target)
  if self.scope == "commits" then
    if not (target.commit and target.file and target.hunk and target.line) then return nil end
    local commit = self.commits[target.commit]
    local file = commit.files[target.file]
    return self:line_identity(file.hunks[target.hunk].lines[target.line], file.path,
      self:commit_owner(commit))
  end
  if not (target.cfile and target.hunk and target.line) then return nil end
  local cf = self.combined_files[target.cfile]
  return self:line_identity(cf.hunks[target.hunk].lines[target.line], cf.path,
    self:combined_owner(cf.path))
end

-- Toggle seen on the cursor's target. The action is decided by which section the
-- target renders in, never a symmetric toggle: `m` on a seen-section row can
-- only unmark, on an unseen-section row can only mark. A hunk row carries that
-- section in `target.sec`; a file/commit/cfile header (no section) falls back to
-- whether every addressed identity is already seen. Mark/unmark is defined
-- solely as add/remove over the target's changed-line identities; both scopes go
-- through the unified identity store, so placement and the action agree.
function Session:toggle_seen(row)
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  if not target then return end
  -- A marker row/line unmarks its run rather than toggling the whole hunk.
  if target.marker then return self:unmark_marker(target) end
  if target.seen then return end
  if self.scope == "commits" then
    if not target.commit then return end
  else
    if not target.cfile then return end
  end
  local ids = self:target_identities(target)
  local op
  if target.sec == "seen" then
    op = "unmark"
  elseif target.sec == "unseen" then
    op = "mark"
  else
    op = self.store:all_seen(ids) and "unmark" or "mark"
  end
  local changed, seen_keys = {}, {}
  for _, id in ipairs(ids) do
    if (op == "mark") ~= self.store:is_seen(id) then
      changed[#changed + 1] = id
      seen_keys[self:seen_collapse_key(id)] = true
    end
  end
  if #changed == 0 then return end
  local action = { kind = "seen", op = op, ids = changed }
  -- Marking always re-collapses the destination seen section, even if it had been
  -- explicitly expanded: clearing the override restores the collapsed default.
  if op == "mark" then
    for k in pairs(seen_keys) do self.collapse[k] = nil end
  end
  -- Resolve the next hunk to land on *before* marking: marking relocates rows
  -- (the cursor's row number is preserved by render but its semantic target
  -- changes), so deciding afterwards skips a hunk. A hunk's identity
  -- (commit/file/cfile + hunk index) is stable across the seen-move.
  -- Marking advances to the next still-unseen hunk; unmarking lands on the next
  -- seen hunk of the same file (or the file's first unseen hunk when none remain).
  local dest_key = op == "unmark" and self:revive_dest_key(row, target) or self:next_hunk_key(row)
  self:perform(action)
  self:render()
  self:move_to_hunk_key(dest_key)
end

-- The identity of the next still-unseen hunk after `row`'s hunk, in document
-- order. Captured before a mark so the cursor can reliably land on it once the
-- just-marked hunk's rows relocate.
function Session:next_hunk_key(row)
  local cur_key = hunk_key(self.row_map[row])
  local best, best_t
  for r, t in pairs(self.row_map) do
    if t.hunk and not t.line and t.sec ~= "seen" and hunk_key(t) ~= cur_key then
      if r > row and (not best or r < best) then best, best_t = r, t end
    end
  end
  return hunk_key(best_t)
end

-- Where to land after un-marking the hunk at `row`: the next *seen* hunk of the
-- same file after it (still in the seen section), or, when none remain, the
-- first unseen hunk of that file. Captured before the mark so the cursor can
-- reliably land once the just-revived hunk's rows relocate.
function Session:revive_dest_key(row, target)
  local cur_key = hunk_key(target)
  local best, best_t
  for r, t in pairs(self.row_map) do
    if t.hunk and not t.line and t.sec == "seen" and same_file(t, target)
      and hunk_key(t) ~= cur_key and r > row and (not best or r < best) then
      best, best_t = r, t
    end
  end
  if best_t then return hunk_key(best_t) end
  best, best_t = nil, nil
  for r, t in pairs(self.row_map) do
    if t.hunk and not t.line and t.sec == "unseen" and same_file(t, target)
      and (not best or r < best) then
      best, best_t = r, t
    end
  end
  return best_t and hunk_key(best_t) or cur_key
end

-- Park the cursor on a hunk header row and scroll so as much of the hunk as
-- possible is visible: if its last row is below the viewport, scroll down until
-- the bottom shows -- but never so far that the header itself scrolls off the
-- top. Only ever scrolls down (revealing more of the hunk), never up.
function Session:move_to_hunk_row(row)
  if not (self.win and api.nvim_win_is_valid(self.win)) then return end
  pcall(api.nvim_win_set_cursor, self.win, { row + 1, 0 })
  local key = hunk_key(self.row_map[row])
  if not key then return end
  local last = row
  for r, t in pairs(self.row_map) do
    if hunk_key(t) == key and r > last then last = r end
  end
  api.nvim_win_call(self.win, function()
    local view = vim.fn.winsaveview()
    local height = api.nvim_win_get_height(self.win)
    local top = view.topline - 1
    local bottom = top + height - 1
    if last > bottom then
      local new_top = math.max(top, math.min(last - height + 1, row))
      view.topline = new_top + 1
      vim.fn.winrestview(view)
    end
  end)
end

-- Move the cursor to the rendered header row of the hunk with `key`, if any.
function Session:move_to_hunk_key(key)
  if not key then return self:move_to_next_hunk() end
  if not (self.win and api.nvim_win_is_valid(self.win)) then return end
  for r, t in pairs(self.row_map) do
    if t.hunk and not t.line and hunk_key(t) == key then
      return self:move_to_hunk_row(r)
    end
  end
  self:move_to_next_hunk()
end

-- After marking something seen its rows relocate into the (collapsed) seen
-- section, so park the cursor on the header of the next still-rendered unseen
-- hunk. Document/buffer order at or after the prior cursor row is exactly the
-- next remaining work, since render preserves the cursor's row number.
function Session:move_to_next_hunk()
  if not (self.win and api.nvim_win_is_valid(self.win)) then return end
  local cur = self:cursor_row()
  local best
  for r, t in pairs(self.row_map) do
    if t.hunk and not t.line and t.sec ~= "seen" then
      if r >= cur and (not best or r < best) then best = r end
    end
  end
  if best then self:move_to_hunk_row(best) end
end

-- Move the cursor to the nearest rendered row matching `pred` in the given
-- direction. Collapsed sections are absent from row_map, so visible navigation
-- naturally skips them.
function Session:nav_to(pred, forward)
  if not (self.win and api.nvim_win_is_valid(self.win)) then return end
  local cur = self:cursor_row()
  local best
  for r, t in pairs(self.row_map) do
    if pred(t) then
      if forward then
        if r > cur and (not best or r < best) then best = r end
      else
        if r < cur and (not best or r > best) then best = r end
      end
    end
  end
  if best then
    local t = self.row_map[best]
    if t.hunk and not t.line and not t.seen then
      self:move_to_hunk_row(best)
    else
      pcall(api.nvim_win_set_cursor, self.win, { best + 1, 0 })
    end
  end
end

local function is_hunk_row(t)
  return t.hunk and not t.line and not t.seen
end

local function is_file_row(t)
  return (t.file or t.cfile) and not t.hunk and not t.line and not t.seen and not t.unseen
end

function Session:next_hunk() self:nav_to(is_hunk_row, true) end
function Session:prev_hunk() self:nav_to(is_hunk_row, false) end
function Session:next_file() self:nav_to(is_file_row, true) end
function Session:prev_file() self:nav_to(is_file_row, false) end

-- Mark a visual span of diff rows seen: fold each selected literal diff-line row
-- to its seen-identity (add/del; context and unowned rows carry none) and mark
-- those not already seen, so the action reverses exactly.
function Session:mark_visual_range(srow, erow)
  if srow > erow then srow, erow = erow, srow end
  local ids = {}
  for row = srow, erow do
    local id = self:row_identity(self.row_map[row])
    if id and not self.store:is_seen(id) then ids[#ids + 1] = id end
  end
  if #ids == 0 then return end
  self:perform({ kind = "seen", op = "mark", ids = ids })
  self:render()
end

-- Unmark a marker run seen: a marker target carries {lo, hi_line} indices into
-- its hunk's lines; fold each to its seen-identity and unmark those currently
-- seen. The derived marker disappears once its lines are no longer seen.
function Session:unmark_marker(target)
  local mk = target.marker
  if not mk then return end
  local hunk, path, owner
  if self.scope == "commits" then
    local commit = self.commits[target.commit]
    local file = commit.files[target.file]
    hunk, path, owner = file.hunks[target.hunk], file.path, self:commit_owner(commit)
  else
    local cf = self.combined_files[target.cfile]
    hunk, path, owner = cf.hunks[target.hunk], cf.path, self:combined_owner(cf.path)
  end
  local ids = {}
  for li = mk.lo, mk.hi_line do
    local id = self:line_identity(hunk.lines[li], path, owner)
    if id and self.store:is_seen(id) then ids[#ids + 1] = id end
  end
  if #ids == 0 then return end
  self:perform({ kind = "seen", op = "unmark", ids = ids })
  self:render()
end
-- ---------------------------------------------------------------------------
-- Comments — content-addressed records { anchor, content[], text } per path,
-- re-anchored at render time (see resolve_comments / collect_comments).
-- ---------------------------------------------------------------------------

-- The single-line authoring target for a row: { path, anchor, content = {text} },
-- or nil if the row is not a literal diff line. `anchor` is the row's flattened
-- diff-line ordinal (the tiebreak / outdated fallback); `content` its text.
function Session:comment_target(row)
  local target = self.row_map[row]
  if not target or not target.line then return nil end
  local file = self:row_file(target)
  if not file then return nil end
  local dl = file.hunks[target.hunk].lines[target.line]
  return { path = file.path, anchor = target_ordinal(file, target), content = { dl.text } }
end

-- The visual-span authoring target: the contiguous run of literal diff-line rows
-- within one file (decoration rows excluded; capture stops at the first ordinal
-- gap), as { path, anchor, content[] }. nil if the span covers no diff rows.
function Session:visual_comment_target(srow, erow)
  local path, anchor, content, prev_ord
  for row = srow, erow do
    local t = self.row_map[row]
    if t and t.line then
      local file = self:row_file(t)
      if file then
        local ord = target_ordinal(file, t)
        local dl = file.hunks[t.hunk].lines[t.line]
        if not path then
          path, anchor, content, prev_ord = file.path, ord, { dl.text }, ord
        elseif file.path == path and ord == prev_ord + 1 then
          content[#content + 1] = dl.text
          prev_ord = ord
        else
          break
        end
      end
    end
  end
  if not path then return nil end
  return { path = path, anchor = anchor, content = content }
end

-- Add a comment record (undoable) from an authoring target + body text.
function Session:add_comment(ct, text)
  if not ct or not text or text == "" then return end
  self:perform({
    kind = "comment", op = "add", path = ct.path,
    record = { anchor = ct.anchor, content = ct.content, text = text },
  })
  self:render()
end

function Session:add_comment_at(row, text)
  if row == nil then row = self:cursor_row() end
  self:add_comment(self:comment_target(row), text)
end

-- Delete a comment attached to the cursor row's line (the line it re-anchors
-- to). With one it is removed directly; with several, the user picks. The
-- removal is an undoable "comment" action (op = "remove"), so `u` restores it.
function Session:delete_comment_at(row)
  if row == nil then row = self:cursor_row() end
  local target = self.row_map[row]
  local file = self:row_file(target)
  if not file or not target.line then return end
  local ord = target_ordinal(file, target)
  local list = self:resolve_comments(file)[ord] or {}
  if #list == 0 then
    vim.notify("glean: no comment on this line", vim.log.levels.INFO)
    return
  end
  local function drop(c)
    if not c then return end
    self:perform({
      kind = "comment", op = "remove", path = c.path,
      record = { anchor = c.anchor, content = c.content, text = c.text },
    })
    self:render()
  end
  if #list == 1 then
    drop(list[1])
  else
    local choices = {}
    for _, c in ipairs(list) do choices[#choices + 1] = c.text end
    vim.ui.select(choices, { prompt = "glean: delete comment" }, function(_, idx)
      if idx then drop(list[idx]) end
    end)
  end
end

-- The comment identity under a cursor row, or nil. Comment rows are real,
-- cursor-addressable buffer lines (carrying { path, anchor, content, text }) so
-- `dd` and `i` can act on the comment beneath the cursor directly.
function Session:comment_under(row)
  if row == nil then row = self:cursor_row() end
  local t = self.row_map[row]
  return t and t.comment or nil
end

-- Delete the comment under the cursor (undoable). No-op off a comment row.
function Session:delete_comment_under(row)
  local c = self:comment_under(row)
  if not c then return end
  self:perform({
    kind = "comment", op = "remove", path = c.path,
    record = { anchor = c.anchor, content = c.content, text = c.text },
  })
  self:render()
end

-- Edit the comment under the cursor in the ephemeral split, replacing its text
-- (undoable). No-op off a comment row.
function Session:edit_comment_under(row)
  local c = self:comment_under(row)
  if not c then return end
  self:open_comment_editor(vim.split(c.text, "\n", { plain = true }), function(text)
    if text == c.text then return end
    self:perform({
      kind = "comment", op = "edit", path = c.path,
      old_record = { anchor = c.anchor, content = c.content, text = c.text },
      record = { anchor = c.anchor, content = c.content, text = text },
    })
    self:render()
  end)
end

-- Open an ephemeral, multi-line comment editor in a split above the glean
-- window, seeded with `initial` lines. `:w` or `<CR>` (normal mode) submits the
-- (trimmed-of-empty) buffer text to `on_submit`; `q` or `<C-c>` cancels. The scratch buffer is
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
  vim.keymap.set("n", "<CR>", function() finish(true) end, { buffer = ebuf, nowait = true, silent = true })
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
-- Ephemeral split diff (fugitive-style).
-- ---------------------------------------------------------------------------

-- Create a read-only scratch buffer holding `path` at `ref`, named
-- `glean://<sha8>:<path>` so the originating commit is visible, with filetype
-- inferred from the path. Empty content (e.g. the pre-image of an added file)
-- yields an empty buffer.
local function show_buffer(git, ref, path)
  local sha = git:rev_parse(ref) or ref
  local content = git:show(ref, path) or ""
  local buf = api.nvim_create_buf(false, true)
  local lines = vim.split(content, "\n", { plain = true })
  if lines[#lines] == "" then lines[#lines] = nil end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  local ft = vim.filetype.match({ filename = path, contents = lines })
  if ft then api.nvim_set_option_value("filetype", ft, { buf = buf }) end
  pcall(api.nvim_buf_set_name, buf, "glean://" .. sha:sub(1, 8) .. ":" .. path)
  return buf
end

-- Resolve a cursor row to the file and the two refs that bound the hunk it
-- belongs to: { path, post_ref, pre_ref, post_lnum, pre_lnum }. `post_ref` is
-- the target (post-image) version and `pre_ref` is the previous (pre-image)
-- version relative to the current commit (commit scope) or the review range
-- (combined scope).
function Session:diff_context(row)
  local target = self.row_map[row]
  if not target or not target.line then return nil end
  local dl, path, post_ref, pre_ref
  if self.scope == "commits" then
    if not target.commit then return nil end
    local commit = self.commits[target.commit]
    local file = commit.files[target.file]
    dl = file.hunks[target.hunk].lines[target.line]
    path = file.path
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
  return {
    path = path, post_ref = post_ref, pre_ref = pre_ref,
    post_lnum = dl.new_lnum, pre_lnum = dl.old_lnum,
  }
end

-- Open an ephemeral side-by-side diff for the file/hunk under the cursor: a
-- full-height vertical split to the right of the glean window with the hunk's
-- previous version on the left and the target version on the right, both in
-- diff mode. The target side opens the live working-tree file when it is the
-- current checkout (so LSP attaches); otherwise it is a read-only `git show`
-- buffer. The previous side is always a read-only `git show` buffer.
function Session:diffsplit(row)
  if row == nil then row = self:cursor_row() end
  local ctx = self:diff_context(row)
  if not ctx then return end
  if self.win and api.nvim_win_is_valid(self.win) then
    api.nvim_set_current_win(self.win)
  end
  vim.cmd("rightbelow vsplit")
  local right_win = api.nvim_get_current_win()
  local abs = self.git.repo_root .. "/" .. ctx.path
  local live = ctx.post_ref == M.WORKTREE or self:ref_is_head(ctx.post_ref)
  if live and vim.fn.filereadable(abs) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(abs))
    right_win = api.nvim_get_current_win()
  else
    api.nvim_win_set_buf(right_win, show_buffer(self.git, ctx.post_ref, ctx.path))
  end
  if ctx.post_lnum then pcall(api.nvim_win_set_cursor, right_win, { ctx.post_lnum, 0 }) end
  vim.cmd("diffthis")
  vim.cmd("leftabove vsplit")
  local left_win = api.nvim_get_current_win()
  api.nvim_win_set_buf(left_win, show_buffer(self.git, ctx.pre_ref, ctx.path))
  if ctx.pre_lnum then pcall(api.nvim_win_set_cursor, left_win, { ctx.pre_lnum, 0 }) end
  vim.cmd("diffthis")
  api.nvim_set_current_win(right_win)
  return right_win, left_win
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
  self._commit_files = self._commit_files or {}
  local files, commits, shas = build_model(self.git, self.base, self.target, self._commit_files)
  if not files then return end
  local store = state_mod.new({ dir = self.state_dir })
  store:load(shas)
  self.files = files
  self.commits = commits
  self.store = store
  self._wt_lines = nil
  self._prov = nil
  -- Del attribution (reverse blame base..HEAD) and its parent->child stack
  -- depend only on the commit set, not on worktree content, so a content-only
  -- reload (the common live-update case) keeps them; they are dropped only when
  -- the commit set actually changes (new commit / amend / rebase).
  local gen = table.concat(shas or {}, ",")
  if gen ~= self._del_gen then
    self._del_attr = nil
    self._del_child = nil
    self._del_gen = gen
  end
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
  local group = api.nvim_create_augroup("glean_cursor_" .. buf, { clear = true })
  api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function() session:highlight_cursor_hunk() end,
  })
  map("n", "=", function() session:toggle_collapse() end)
  map("n", "m", function() session:toggle_seen() end)
  map("x", "m", function()
    local srow = vim.fn.getpos("v")[2] - 1
    local erow = vim.fn.getpos(".")[2] - 1
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    session:mark_visual_range(srow, erow)
  end)
  map("n", "c", function()
    local ct = session:comment_target(session:cursor_row())
    if not ct then
      vim.notify("glean: cannot comment here", vim.log.levels.INFO)
      return
    end
    session:open_comment_editor({}, function(text) session:add_comment(ct, text) end)
  end)
  map("x", "c", function()
    local srow = vim.fn.getpos("v")[2] - 1
    local erow = vim.fn.getpos(".")[2] - 1
    if srow > erow then srow, erow = erow, srow end
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    local ct = session:visual_comment_target(srow, erow)
    if not ct then
      vim.notify("glean: cannot comment here", vim.log.levels.INFO)
      return
    end
    session:open_comment_editor({}, function(text) session:add_comment(ct, text) end)
  end)
  map("n", "i", function() session:edit_comment_under() end)
  map("n", "dd", function() session:delete_comment_under() end)
  map("n", "dc", function() session:delete_comment_at() end)
  map("n", "u", function() session:undo() end)
  map("n", "<C-r>", function() session:redo() end)
  map({ "x", "o" }, "ac", function() session:select_hunk_textobj() end)
  map({ "n", "x" }, "]c", function() session:next_hunk() end)
  map({ "n", "x" }, "[c", function() session:prev_hunk() end)
  map({ "n", "x" }, "]f", function() session:next_file() end)
  map({ "n", "x" }, "[f", function() session:prev_file() end)
  map("n", "<CR>", function() session:jump() end)
  map("n", "D", function() session:diffsplit() end)
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
  local commit_files = {}
  local files, commit_list, shas = build_model(git, opts.base, opts.target, commit_files)
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
    _commit_files = commit_files,
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
  -- Detect the repo's trunk from origin/HEAD (e.g. origin/dev, origin/main) so
  -- we don't assume a "main" branch; fall back to the configured default_base.
  local trunk = git:default_trunk() or M.config.default_base
  local trunk_branch = trunk:gsub("^[^/]+/", "")
  local base
  if git:current_branch() == trunk_branch then
    base = git:upstream()
  else
    base = git:merge_base(trunk, "HEAD")
  end
  return base or trunk, M.WORKTREE
end

-- Open a review of "current branch + dirty". An explicit `opts.base` overrides
-- the resolved fork-point/upstream base; the target is always the work tree.
function M.open_dirty(opts)
  opts = opts or {}
  local repo_root = opts.repo_root
    or resolve_repo_root(api.nvim_buf_get_name(0))
  assert(repo_root, "glean: could not find a git repo root")
  local git = git_mod.new({ repo_root = repo_root, run = opts.run })
  local base, target = M.resolve_dirty(git)
  return M.open(vim.tbl_extend("force", opts, {
    repo_root = repo_root, base = opts.base or base, target = target,
  }))
end
-- A foreground-only spec carrying just the visible attributes of `src` (its
-- foreground color + emphasis), dropping its background. Used for aligned diff
-- lines, whose background moves to the changed spans only.
local function fg_only(src)
  local hl = api.nvim_get_hl(0, { name = src, link = false })
  return { fg = hl.fg, bold = hl.bold, italic = hl.italic }
end

-- Highlight groups are (re)applied here and on every ColorScheme, because the
-- foreground-only GleanAddText/GleanDelText are derived from the resolved
-- DiffAdd/DiffDelete colors rather than a static link.
local function setup_highlights()
  api.nvim_set_hl(0, "GleanFileHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanCommitHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanHunkHeader", { link = "Comment", default = true })
  api.nvim_set_hl(0, "GleanAdd", { link = "DiffAdd", default = true })
  api.nvim_set_hl(0, "GleanDel", { link = "DiffDelete", default = true })
  -- Emphasis on a changed span uses the full diff background (green/red).
  api.nvim_set_hl(0, "GleanAddEmph", { link = "DiffAdd", default = true })
  api.nvim_set_hl(0, "GleanDelEmph", { link = "DiffDelete", default = true })
  -- The body of an aligned line: just colored text, no background.
  api.nvim_set_hl(0, "GleanAddText", fg_only("DiffAdd"))
  api.nvim_set_hl(0, "GleanDelText", fg_only("DiffDelete"))
  api.nvim_set_hl(0, "GleanContext", { link = "Normal", default = true })
  api.nvim_set_hl(0, "GleanSeen", { link = "NonText", default = true })
  api.nvim_set_hl(0, "GleanComment", { link = "WarningMsg", default = true })
  api.nvim_set_hl(0, "GleanModeHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanCurrentHunk", { link = "Identifier", default = true })
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  setup_highlights()
  api.nvim_create_autocmd("ColorScheme", {
    group = api.nvim_create_augroup("GleanHighlights", { clear = true }),
    callback = setup_highlights,
  })
  api.nvim_create_user_command("Glean", function(o)
    local args = o.fargs
    if #args == 0 then
      M.open_dirty()
      return
    end
    if #args == 1 then
      M.open_dirty({ base = args[1] })
      return
    end
    M.open({ base = args[1], target = args[2] })
  end, { nargs = "*" })
end

-- Internal helpers exposed for unit tests only.
M._internal = {
  hunk_marker_runs = hunk_marker_runs,
  marker_key = marker_key,
  cmarker_key = cmarker_key,
}

return M
