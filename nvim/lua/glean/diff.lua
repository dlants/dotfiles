-- glean.diff: parse unified-diff text into FileEntries / Hunks / DiffLines.
--
-- The parser is pure (no git, no IO) so it is trivially testable: feed it the
-- text produced by `git diff` and it returns an ordered list of FileEntries.
--
-- Each DiffLine carries the new-file line number (`new_lnum`) which is the
-- stable addressing basis for review marks: a `(commit, path, new_lnum)` tuple
-- never moves because a commit's post-image blob is immutable.
local M = {}

-- A DiffLine: { kind = "context"|"add"|"del", text, old_lnum, new_lnum }.
--   - add lines have a new_lnum but no old_lnum.
--   - del lines have an old_lnum but no new_lnum.
--   - context lines have both.

-- Parse a single `@@ -a,b +c,d @@` hunk header. The counts are optional and
-- default to 1 when omitted (git omits a count of 1).
local function parse_hunk_header(line)
  local old_start, old_count, new_start, new_count =
    line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then return nil end
  return {
    old_start = tonumber(old_start),
    old_count = tonumber(old_count) or 1,
    new_start = tonumber(new_start),
    new_count = tonumber(new_count) or 1,
    header = line,
    lines = {},
  }
end

-- Strip the `a/` or `b/` prefix git puts on diff paths, honoring quoted paths
-- only minimally (we keep it simple; review-sized diffs use plain paths).
local function strip_prefix(p)
  return (p:gsub("^[ab]/", ""))
end

-- Parse the path from a `diff --git a/<old> b/<new>` header. Returns
-- old_path, new_path (prefix-stripped). Falls back to nil on no match.
local function parse_git_header(line)
  local old_p, new_p = line:match("^diff %-%-git (%S+) (%S+)$")
  if not old_p then return nil, nil end
  return strip_prefix(old_p), strip_prefix(new_p)
end

-- Parse full unified-diff text (possibly spanning many files) into an ordered
-- list of FileEntries:
--   { path, old_path, kind = "add"|"delete"|"modify"|"rename", hunks }
-- `collapsed` is intentionally not set here; it is ephemeral view-state owned by
-- the renderer.
function M.parse(text)
  local files = {}
  local file = nil
  local hunk = nil
  local old_lnum, new_lnum = 0, 0

  local function finish_hunk()
    if file and hunk then
      file.hunks[#file.hunks + 1] = hunk
      hunk = nil
    end
  end

  local function finish_file()
    finish_hunk()
    file = nil
  end

  for line in (text .. "\n"):gmatch("(.-)\n") do
    local old_p, new_p = parse_git_header(line)
    if old_p then
      finish_file()
      file = {
        path = new_p,
        old_path = old_p,
        kind = "modify",
        hunks = {},
      }
      files[#files + 1] = file
    elseif file and not hunk and line:match("^new file mode") then
      file.kind = "add"
    elseif file and not hunk and line:match("^deleted file mode") then
      file.kind = "delete"
    elseif file and not hunk and line:match("^rename from ") then
      file.kind = "rename"
    elseif file and not hunk and line:match("^rename to ") then
      file.kind = "rename"
    elseif file and line:match("^%-%-%- ") then
      -- old-file marker; for added files this is `/dev/null`.
    elseif file and line:match("^%+%+%+ ") then
      local p = line:match("^%+%+%+ (.+)$")
      if p and p ~= "/dev/null" then file.path = strip_prefix(p) end
    elseif file and line:match("^@@") then
      finish_hunk()
      hunk = parse_hunk_header(line)
      if hunk then
        old_lnum = hunk.old_start
        new_lnum = hunk.new_start
      end
    elseif hunk then
      local marker = line:sub(1, 1)
      local body = line:sub(2)
      if marker == "+" then
        hunk.lines[#hunk.lines + 1] =
          { kind = "add", text = body, new_lnum = new_lnum }
        new_lnum = new_lnum + 1
      elseif marker == "-" then
        hunk.lines[#hunk.lines + 1] =
          { kind = "del", text = body, old_lnum = old_lnum }
        old_lnum = old_lnum + 1
      elseif marker == " " then
        hunk.lines[#hunk.lines + 1] =
          { kind = "context", text = body, old_lnum = old_lnum, new_lnum = new_lnum }
        old_lnum = old_lnum + 1
        new_lnum = new_lnum + 1
      elseif marker == "\\" then
        -- "\ No newline at end of file" — decoration, not a line.
      end
    end
  end

  finish_file()
  return files
end

return M
