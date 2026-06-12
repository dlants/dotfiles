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
-- provenance parsing lives in provenance.lua (Stage 4).
function Git:blame(ref, path, first, last)
  local args = { "blame", "-p" }
  if first and last then
    args[#args + 1] = "-L"; args[#args + 1] = first .. "," .. last
  end
  args[#args + 1] = ref
  args[#args + 1] = "--"
  args[#args + 1] = path
  return self:run(args)
end

-- Contents of a path at a ref (`git show REF:path`). Used by jump-to-source.
function Git:show(ref, path)
  return self:run({ "show", ref .. ":" .. path })
end

return M
