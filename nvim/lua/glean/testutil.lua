-- glean.testutil: a tiny dependency-free assert harness shared by glean's
-- headless tests (run via `nvim -l`). Mirrors needle/score_test.lua's style but
-- factored out so every `glean/*_test.lua` reports the same way.
local M = {}

function M.new()
  local h = {
    pass = 0,
    fail = 0,
    failures = {},
  }

  function h.record_fail(name, detail)
    h.fail = h.fail + 1
    h.failures[#h.failures + 1] = { name = name, detail = detail }
  end

  function h.assert_eq(name, actual, expected)
    if actual == expected then
      h.pass = h.pass + 1
    else
      h.record_fail(name, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
    end
  end

  function h.assert_true(name, cond, detail)
    if cond then
      h.pass = h.pass + 1
    else
      h.record_fail(name, detail or "expected true")
    end
  end

  -- Print a summary and exit(1) on any failure, exit(0) otherwise.
  function h.finish()
    io.stdout:write(("\n%d passed, %d failed\n"):format(h.pass, h.fail))
    if h.fail > 0 then
      io.stdout:write("\nFailures:\n")
      for _, f in ipairs(h.failures) do
        io.stdout:write(("  - %s: %s\n"):format(f.name, f.detail or ""))
      end
      os.exit(1)
    end
  end

  return h
end

-- Build a hermetic throwaway git repo in a tempname() dir. `spec` is a list of
-- commits; each commit is { msg = <string>, files = { [path] = content } }.
-- Files listed in a commit are written (overwriting) and committed together.
-- Returns { root, run, shas } where `shas[i]` is the sha of commit i and `run`
-- runs git in the repo and returns trimmed stdout (asserting success).
function M.make_repo(spec)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  local env = {
    GIT_CONFIG_GLOBAL = "/dev/null",
    GIT_CONFIG_SYSTEM = "/dev/null",
    HOME = root,
    GIT_AUTHOR_NAME = "Glean Test",
    GIT_AUTHOR_EMAIL = "glean@example.com",
    GIT_COMMITTER_NAME = "Glean Test",
    GIT_COMMITTER_EMAIL = "glean@example.com",
    GIT_AUTHOR_DATE = "2020-01-01T00:00:00 +0000",
    GIT_COMMITTER_DATE = "2020-01-01T00:00:00 +0000",
  }

  local function run(args)
    local cmd = { "git" }
    for _, a in ipairs(args) do cmd[#cmd + 1] = a end
    local res = vim.system(cmd, { cwd = root, env = env, text = true }):wait()
    if res.code ~= 0 then
      error(("git %s failed: %s"):format(table.concat(args, " "), res.stderr or ""))
    end
    return (res.stdout or ""):gsub("%s+$", "")
  end

  run({ "init", "-q", "-b", "main" })
  run({ "config", "user.name", "Glean Test" })
  run({ "config", "user.email", "glean@example.com" })

  local shas = {}
  for _, commit in ipairs(spec) do
    for path, content in pairs(commit.files or {}) do
      local full = root .. "/" .. path
      local dir = vim.fs.dirname(full)
      if dir and dir ~= "" then vim.fn.mkdir(dir, "p") end
      local f = assert(io.open(full, "w"))
      f:write(content)
      f:close()
      run({ "add", "--", path })
    end
    run({ "commit", "-q", "-m", commit.msg or "commit" })
    shas[#shas + 1] = run({ "rev-parse", "HEAD" })
  end

  return { root = root, run = run, shas = shas, env = env }
end

return M
