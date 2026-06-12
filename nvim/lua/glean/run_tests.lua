-- Run every glean/*_test.lua in one shot. From the repo root:
--   nvim -l nvim/lua/glean/run_tests.lua
-- Exits 0 only if all suites pass; nonzero otherwise.
local this_script = debug.getinfo(1, "S").source:sub(2)
local this_dir = this_script:match("(.+)/[^/]+$") or "."

local tests = vim.fn.glob(this_dir .. "/*_test.lua", true, true)
table.sort(tests)

local failed = 0
for _, t in ipairs(tests) do
  io.stdout:write("== " .. vim.fn.fnamemodify(t, ":t") .. " ==\n")
  local res = vim.system({ "nvim", "-l", t }):wait()
  io.stdout:write(res.stdout or "")
  if (res.stderr or "") ~= "" then io.stdout:write(res.stderr) end
  if res.code ~= 0 then failed = failed + 1 end
end

if failed > 0 then
  io.stdout:write(("\n%d suite(s) failed\n"):format(failed))
  os.exit(1)
end
io.stdout:write("\nall suites passed\n")
