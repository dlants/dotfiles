-- Tier 1 tests for glean.diff (pure unified-diff parsing). Run with:
--   nvim -l nvim/lua/glean/diff_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local diff = require("glean.diff")
local h = require("glean.testutil").new()

-- A simple modify: one hunk replacing a line, with surrounding context.
do
  local text = table.concat({
    "diff --git a/foo.txt b/foo.txt",
    "index 1111111..2222222 100644",
    "--- a/foo.txt",
    "+++ b/foo.txt",
    "@@ -1,3 +1,3 @@",
    " one",
    "-two",
    "+TWO",
    " three",
  }, "\n")
  local files = diff.parse(text)
  h.assert_eq("modify: one file", #files, 1)
  local f = files[1]
  h.assert_eq("modify: path", f.path, "foo.txt")
  h.assert_eq("modify: kind", f.kind, "modify")
  h.assert_eq("modify: one hunk", #f.hunks, 1)
  local lines = f.hunks[1].lines
  h.assert_eq("modify: 4 diff lines", #lines, 4)
  h.assert_eq("modify: l1 context", lines[1].kind, "context")
  h.assert_eq("modify: l1 new_lnum", lines[1].new_lnum, 1)
  h.assert_eq("modify: l1 old_lnum", lines[1].old_lnum, 1)
  h.assert_eq("modify: l2 del", lines[2].kind, "del")
  h.assert_eq("modify: l2 old_lnum", lines[2].old_lnum, 2)
  h.assert_eq("modify: l2 no new_lnum", lines[2].new_lnum, nil)
  h.assert_eq("modify: l3 add", lines[3].kind, "add")
  h.assert_eq("modify: l3 new_lnum", lines[3].new_lnum, 2)
  h.assert_eq("modify: l3 no old_lnum", lines[3].old_lnum, nil)
  h.assert_eq("modify: l4 context new_lnum", lines[4].new_lnum, 3)
end

-- Added file: kind=add, new_lnums increment from 1.
do
  local text = table.concat({
    "diff --git a/new.txt b/new.txt",
    "new file mode 100644",
    "index 0000000..3333333",
    "--- /dev/null",
    "+++ b/new.txt",
    "@@ -0,0 +1,2 @@",
    "+alpha",
    "+beta",
  }, "\n")
  local files = diff.parse(text)
  h.assert_eq("add: kind", files[1].kind, "add")
  local lines = files[1].hunks[1].lines
  h.assert_eq("add: l1 new_lnum", lines[1].new_lnum, 1)
  h.assert_eq("add: l2 new_lnum", lines[2].new_lnum, 2)
end

-- Deleted file: kind=delete.
do
  local text = table.concat({
    "diff --git a/gone.txt b/gone.txt",
    "deleted file mode 100644",
    "index 4444444..0000000",
    "--- a/gone.txt",
    "+++ /dev/null",
    "@@ -1,2 +0,0 @@",
    "-x",
    "-y",
  }, "\n")
  local files = diff.parse(text)
  h.assert_eq("delete: kind", files[1].kind, "delete")
  h.assert_eq("delete: path keeps old", files[1].path, "gone.txt")
  h.assert_eq("delete: l1 old_lnum", files[1].hunks[1].lines[1].old_lnum, 1)
end

-- Multi-hunk, multi-file: line numbers reset/advance correctly per hunk.
do
  local text = table.concat({
    "diff --git a/a.txt b/a.txt",
    "--- a/a.txt",
    "+++ b/a.txt",
    "@@ -1,2 +1,2 @@",
    " a1",
    "+a-added",
    "-a2",
    "@@ -10,2 +10,3 @@",
    " a10",
    "+a-added2",
    " a11",
    "diff --git a/b.txt b/b.txt",
    "--- a/b.txt",
    "+++ b/b.txt",
    "@@ -5,1 +5,1 @@",
    "-b5",
    "+B5",
  }, "\n")
  local files = diff.parse(text)
  h.assert_eq("multi: 2 files", #files, 2)
  h.assert_eq("multi: a 2 hunks", #files[1].hunks, 2)
  local hunk2 = files[1].hunks[2]
  h.assert_eq("multi: hunk2 new_start", hunk2.new_start, 10)
  h.assert_eq("multi: hunk2 l1 new_lnum", hunk2.lines[1].new_lnum, 10)
  h.assert_eq("multi: hunk2 add new_lnum", hunk2.lines[2].new_lnum, 11)
  h.assert_eq("multi: hunk2 ctx new_lnum", hunk2.lines[3].new_lnum, 12)
  h.assert_eq("multi: b path", files[2].path, "b.txt")
  h.assert_eq("multi: b5 add new_lnum", files[2].hunks[1].lines[2].new_lnum, 5)
end

-- "No newline at end of file" marker is decoration, not a line; default counts.
do
  local text = table.concat({
    "diff --git a/c.txt b/c.txt",
    "--- a/c.txt",
    "+++ b/c.txt",
    "@@ -1 +1 @@",
    "-old",
    "\\ No newline at end of file",
    "+new",
    "\\ No newline at end of file",
  }, "\n")
  local files = diff.parse(text)
  local lines = files[1].hunks[1].lines
  h.assert_eq("nonewline: 2 real lines", #lines, 2)
  h.assert_eq("nonewline: del", lines[1].kind, "del")
  h.assert_eq("nonewline: add", lines[2].kind, "add")
  h.assert_eq("nonewline: add new_lnum", lines[2].new_lnum, 1)
  h.assert_eq("nonewline: default old_count", files[1].hunks[1].old_count, 1)
end

-- Stability: parsing the same text twice yields identical new_lnums.
do
  local text = table.concat({
    "diff --git a/d.txt b/d.txt",
    "--- a/d.txt",
    "+++ b/d.txt",
    "@@ -1,1 +1,2 @@",
    " keep",
    "+extra",
  }, "\n")
  local a = diff.parse(text)
  local b = diff.parse(text)
  h.assert_eq("stable: same new_lnum",
    a[1].hunks[1].lines[2].new_lnum, b[1].hunks[1].lines[2].new_lnum)
end

h.finish()
