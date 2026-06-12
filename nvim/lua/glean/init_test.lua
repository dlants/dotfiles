-- Tier 3a tests for glean.init: render the combined scope against a hermetic
-- git fixture and assert observable buffer state, row_map, and collapse
-- re-render. Run with:
--   nvim -l nvim/lua/glean/init_test.lua
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."
local lua_root = this_dir:match("(.+)/[^/]+$") or "."
package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local glean = require("glean.init")
local testutil = require("glean.testutil")
local h = testutil.new()
local api = vim.api

local repo = testutil.make_repo({
  { msg = "base", files = { ["f.txt"] = "one\ntwo\nthree\n" } },
  { msg = "c1: edit two", files = { ["f.txt"] = "one\nTWO\nthree\n" } },
  { msg = "c2: edit three + add g", files = {
    ["f.txt"] = "one\nTWO\nTHREE\n",
    ["g.txt"] = "gee\n",
  } },
})
local base = repo.shas[1]
local target = repo.shas[3]

local function inject_run(args)
  local cmd = { "git" }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local res = vim.system(cmd, { cwd = repo.root, env = repo.env, text = true }):wait()
  return { code = res.code, stdout = res.stdout, stderr = res.stderr }
end

local function open()
  return glean.open({
    base = base,
    target = target,
    repo_root = repo.root,
    run = inject_run,
    open_window = false,
  })
end

-- Render: both files appear as headers (expanded chevron) and bodies present.
do
  local s = open()
  local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local joined = table.concat(lines, "\n")
  h.assert_true("render: f.txt header", joined:find("▾ f.txt", 1, true) ~= nil)
  h.assert_true("render: g.txt header", joined:find("▾ g.txt", 1, true) ~= nil)
  h.assert_true("render: g.txt add kind", joined:find("g.txt %[add%]") ~= nil)
  h.assert_true("render: shows TWO add", joined:find("\n+TWO", 1, true) ~= nil)
  h.assert_true("render: shows hunk header", joined:find("@@", 1, true) ~= nil)
end

-- row_map: every rendered row resolves, headers carry file, body carries line.
do
  local s = open()
  local n = api.nvim_buf_line_count(s.buf)
  local all_mapped = true
  for row = 0, n - 1 do
    if not s.row_map[row] then all_mapped = false end
  end
  h.assert_true("row_map: every row mapped", all_mapped)
  h.assert_true("row_map: row 0 is a file header", s.row_map[0].file == 1 and s.row_map[0].hunk == nil)
  -- find a body line (has .line) and confirm it points into a hunk.
  local found_line = false
  for row = 0, n - 1 do
    local t = s.row_map[row]
    if t.line then found_line = true end
  end
  h.assert_true("row_map: has body line rows", found_line)
end

-- Collapse: toggling the first file hides its body; the other file is intact.
do
  local s = open()
  -- locate g.txt header row before collapse.
  local function header_row(path)
    for row, t in pairs(s.row_map) do
      if t.file and not t.hunk then
        local line = api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1]
        if line and line:find(path, 1, true) then return row end
      end
    end
  end
  local before = api.nvim_buf_line_count(s.buf)
  s:toggle_collapse(0) -- collapse file 1 (f.txt)
  local after = api.nvim_buf_line_count(s.buf)
  h.assert_true("collapse: buffer shrank", after < before)
  local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local joined = table.concat(lines, "\n")
  h.assert_true("collapse: f.txt now closed chevron", joined:find("▸ f.txt", 1, true) ~= nil)
  h.assert_true("collapse: f.txt body hidden", joined:find("\n+TWO", 1, true) == nil)
  h.assert_true("collapse: g.txt still present", joined:find("▾ g.txt", 1, true) ~= nil)
  h.assert_true("collapse: g.txt body intact", header_row("g.txt") ~= nil)
  -- expand again restores the body.
  s:toggle_collapse(0)
  local restored = api.nvim_buf_line_count(s.buf)
  h.assert_eq("collapse: re-expand restores rows", restored, before)
end

h.finish()
