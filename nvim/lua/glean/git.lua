-- glean.git: git plumbing for glean.
--
-- All invocations are read-only and scoped to an explicit `repo_root`. The
-- module is constructed via `git.new(opts)` so tests can inject a custom runner
-- (e.g. to stub git or point at a throwaway repo) and never rely on cwd.
local diff = require("glean.diff")

local M = {}

-- Discover the repo root for a buffer path by walking upward for `.git`,
-- mirroring shuck's search-root discovery. Returns nil if none is found.
function M.discover_repo_root(path)
  local start = path
  if not start or start == "" then start = vim.fn.getcwd() end
  if vim.fn.isdirectory(start) == 0 then start = vim.fs.dirname(start) end
  local found = vim.fs.find(".git", { upward = true, path = start })
  if found and #found > 0 then return vim.fs.dirname(found[1]) end
  return nil
end

local Git = {}
Git.__index = Git

-- Create a git handle. `opts`:
--   - repo_root (required): cwd for all git calls.
--   - run (optional): function(args) -> { code, stdout, stderr } used to run
--     git. Defaults to a synchronous `vim.system` runner. Injectable for tests.
function M.new(opts)
  assert(opts and opts.repo_root, "glean.git.new requires repo_root")
  local self = setmetatable({}, Git)
  self.repo_root = opts.repo_root
  self._run = opts.run
  return self
end

-- Run git with the given argument list (not including the leading "git").
-- Returns stdout on success, or nil + stderr on failure.
function Git:run(args)
  if self._run then
    local res = self._run(args)
    if res.code ~= 0 then return nil, res.stderr or "" end
    return res.stdout or ""
  end
  local cmd = { "git" }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local res = vim.system(cmd, { cwd = self.repo_root, text = true }):wait()
  if res.code ~= 0 then return nil, res.stderr or "" end
  return res.stdout or ""
end

-- Resolve a ref to a concrete 40-char sha. Returns nil on failure.
function Git:rev_parse(ref)
  local out, err = self:run({ "rev-parse", ref })
  if not out then return nil, err end
  return (out:gsub("%s+$", ""))
end

-- The current branch name (`HEAD` when detached). Used for buffer labels.
function Git:current_branch()
  local out = self:run({ "rev-parse", "--abbrev-ref", "HEAD" })
  if not out then return nil end
  return (out:gsub("%s+$", ""))
end

-- The upstream tracking ref for `ref` (default HEAD), e.g. `origin/main`.
-- Returns the ref name, or nil when no upstream is configured.
function Git:upstream(ref)
  local out = self:run({ "rev-parse", "--abbrev-ref", "--symbolic-full-name",
    (ref or "HEAD") .. "@{upstream}" })
  if not out then return nil end
  out = out:gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

-- List commits on `base..target` in chronological order (oldest first).
-- Returns a list of { sha, summary }.
function Git:commits(base, target)
  local range = base .. ".." .. target
  local out, err = self:run({
    "log", "--reverse", "--no-color", "--format=%H%x09%s", range,
  })
  if not out then return nil, err end
  local commits = {}
  for line in out:gmatch("([^\n]+)") do
    local sha, summary = line:match("^(%x+)\t(.*)$")
    if sha then
      commits[#commits + 1] = { sha = sha, summary = summary }
    end
  end
  return commits
end

-- Parsed diff of a single commit against its first parent (`C^..C`), i.e. the
-- changes that commit introduced. Returns a list of FileEntries.
function Git:commit_diff(sha, path)
  local args = { "diff", "--no-color", sha .. "^", sha }
  if path then args[#args + 1] = "--"; args[#args + 1] = path end
  local out, err = self:run(args)
  if not out then return nil, err end
  return diff.parse(out)
end

-- Parsed diff of the working tree against HEAD (`git diff HEAD`: staged +
-- unstaged tracked changes). This is the floating commit's tracked-file content.
-- Returns a list of FileEntries.
function Git:worktree_diff(path)
  local args = { "diff", "--no-color", "HEAD" }
  if path then args[#args + 1] = "--"; args[#args + 1] = path end
  local out, err = self:run(args)
  if not out then return nil, err end
  return diff.parse(out)
end

-- Parsed diff from `base` to the working tree (two-dot `git diff <base>`):
-- everything that changed since `base`, committed and uncommitted. Used as the
-- combined-scope net diff when the review target is the work tree. Returns a
-- list of FileEntries.
function Git:diff_to_worktree(base, path)
  local args = { "diff", "--no-color", base }
  if path then args[#args + 1] = "--"; args[#args + 1] = path end
  local out, err = self:run(args)
  if not out then return nil, err end
  return diff.parse(out)
end

-- Resolve the merge base (fork point) of two refs (`git merge-base a b`).
-- Returns the sha, or nil + stderr on failure.
function Git:merge_base(a, b)
  local out, err = self:run({ "merge-base", a, b })
  if not out then return nil, err end
  return (out:gsub("%s+$", ""))
end

-- Untracked, non-ignored files synthesized as all-addition FileEntries so they
-- attach to the floating commit alongside tracked dirty edits. Read-only: we
-- never `git add -N`. Each entry has kind "add" and a single hunk whose lines
-- are the working file's lines, each an `add` with new_lnum = 1..N (no old_lnum,
-- no deletions). Binary or unreadable files are skipped.
function Git:untracked(path)
  local args = { "ls-files", "--others", "--exclude-standard", "-z" }
  if path then args[#args + 1] = "--"; args[#args + 1] = path end
  local out, err = self:run(args)
  if not out then return nil, err end
  local files = {}
  for p in out:gmatch("([^%z]+)") do
    local full = self.repo_root .. "/" .. p
    local ok, lines = pcall(vim.fn.readfile, full)
    local binary = false
    if ok and lines then
      for _, l in ipairs(lines) do
        if l:find("\0", 1, true) then binary = true; break end
      end
    end
    if ok and lines and not binary then
      local dlines = {}
      for i, text in ipairs(lines) do
        dlines[#dlines + 1] = { kind = "add", text = text, new_lnum = i }
      end
      local n = #lines
      files[#files + 1] = {
        path = p,
        old_path = p,
        kind = "add",
        hunks = (n > 0) and { {
          old_start = 0,
          old_count = 0,
          new_start = 1,
          new_count = n,
          header = ("@@ -0,0 +1,%d @@"):format(n),
          lines = dlines,
        } } or {},
      }
    end
  end
  return files
end

-- Parsed net diff `base...target` (three-dot: changes on target since it
-- diverged from base — "what's in the branch that isn't in main"). Returns a
-- list of FileEntries.
function Git:combined_diff(base, target, path)
  local args = { "diff", "--no-color", base .. "..." .. target }
  if path then args[#args + 1] = "--"; args[#args + 1] = path end
  local out, err = self:run(args)
  if not out then return nil, err end
  return diff.parse(out)
end

-- Parsed diff over an arbitrary range `from..to` for a single path. Used for
-- the tighter `Xe^..TARGET` follow-up re-diff in later stages.
function Git:range_diff(from, to, path)
  local args = { "diff", "--no-color", from .. ".." .. to }
  if path then args[#args + 1] = "--"; args[#args + 1] = path end
  local out, err = self:run(args)
  if not out then return nil, err end
  return diff.parse(out)
end

-- Porcelain blame for a line range of a path at a ref. Returns the raw output;
-- provenance parsing lives in provenance.lua. A nil ref blames the *working
-- tree* (uncommitted lines are attributed to the all-zero sha), which the
-- combined work-tree overlay maps onto the floating commit.
function Git:blame(ref, path, first, last)
  local args = { "blame", "-p" }
  if first and last then
    args[#args + 1] = "-L"; args[#args + 1] = first .. "," .. last
  end
  if ref then args[#args + 1] = ref end
  args[#args + 1] = "--"
  args[#args + 1] = path
  return self:run(args)
end

-- Reverse (forward-walking) porcelain blame over `start_rev..end_rev` for a
-- path. For each line present in `start_rev`'s version, git reports the *last*
-- revision in the range in which the line still existed; the commit that removed
-- it is that revision's child. The porcelain header `<sha> <orig> <final>` then
-- gives, for each `final` line of the start file, the reporting commit `sha` and
-- that line's number `orig` in the reporting commit (the deleter's parent), so
-- combined-scope deletions resolve to the same immutable identity as commit
-- scope. Returns the raw output; parsing reuses provenance.parse_blame.
function Git:reverse_blame(start_rev, end_rev, path)
  return self:run({ "blame", "-p", "--reverse", start_rev .. ".." .. end_rev, "--", path })
end

-- A cheap signature of the working-tree state, used by the live-update timer to
-- skip a rebuild when nothing changed. Combines HEAD, the tracked diff against
-- HEAD (catches in-file content edits), and the porcelain status (catches
-- staging/untracked changes). Returns a short hash, or nil on failure.
function Git:dirty_sig()
  local head = self:run({ "rev-parse", "HEAD" }) or ""
  local diff_out = self:run({ "diff", "--no-color", "HEAD" }) or ""
  local status = self:run({ "status", "--porcelain=v1", "-uall" }) or ""
  return vim.fn.sha256(head .. "\0" .. diff_out .. "\0" .. status)
end

-- Contents of a path at a ref (`git show REF:path`). Used by jump-to-source.
function Git:show(ref, path)
  return self:run({ "show", ref .. ":" .. path })
end

return M
