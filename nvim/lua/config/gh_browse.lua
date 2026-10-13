local M = {}

local default_branch_cache = {}
local repo_name_cache = {}

local function gh_err(msg)
  vim.notify("gh browse: " .. msg, vim.log.levels.ERROR)
end

local function file_dir()
  local p = vim.fn.expand("%:p")
  if p == "" then return nil end
  return vim.fn.fnamemodify(vim.fn.resolve(p), ":h")
end

local function run_in(dir, cmd)
  local out = vim.fn.system("cd " .. vim.fn.shellescape(dir) .. " && " .. cmd)
  return vim.trim(out), vim.v.shell_error
end

-- Returns the toplevel for the file's repo. For submodules this is the
-- submodule root (which has its own remote). For worktrees this is the
-- worktree directory (which shares the parent repo's remote).
local function get_toplevel()
  local dir = file_dir()
  if not dir then
    gh_err("current buffer is not backed by a file on disk")
    return nil
  end
  local out, err = run_in(dir, "git rev-parse --show-toplevel 2>/dev/null")
  if err ~= 0 or out == "" then
    gh_err("not inside a git repository")
    return nil
  end
  return vim.fn.resolve(out)
end

local function get_repo_name(toplevel)
  if repo_name_cache[toplevel] then
    return repo_name_cache[toplevel]
  end
  local out, err = run_in(toplevel, "gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null")
  if err ~= 0 or out == "" then
    gh_err("could not resolve GitHub repo (no remote, or gh not authenticated)")
    return nil
  end
  repo_name_cache[toplevel] = out
  return out
end

local function get_default_branch(toplevel)
  if default_branch_cache[toplevel] then
    return default_branch_cache[toplevel]
  end
  local out, err = run_in(toplevel, "gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null")
  if err ~= 0 or out == "" then
    gh_err("could not determine default branch from GitHub")
    return nil
  end
  default_branch_cache[toplevel] = out
  return out
end

-- Returns the current branch, or nil with an error if HEAD is detached
-- or the branch has not been pushed to a remote that exists on GitHub.
local function get_current_branch(toplevel)
  local branch, err = run_in(toplevel, "git symbolic-ref --short -q HEAD")
  if err ~= 0 or branch == "" then
    gh_err("HEAD is detached; cannot resolve a branch name. Use :Ghom/:Ghlm for the default branch.")
    return nil
  end
  local upstream, uerr = run_in(toplevel, "git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null")
  if uerr ~= 0 or upstream == "" then
    gh_err("branch '" .. branch .. "' has no upstream; push it first or use :Ghom/:Ghlm.")
    return nil
  end
  return branch
end

local function get_repo_relative_path(toplevel)
  local abs_path = vim.fn.resolve(vim.fn.expand("%:p"))
  if vim.startswith(abs_path, toplevel .. "/") then
    return abs_path:sub(#toplevel + 2)
  end
  gh_err("file is outside the resolved repo toplevel: " .. toplevel)
  return nil
end

local function resolve_branch(opts, toplevel)
  if opts.branch == "default" then
    return get_default_branch(toplevel)
  end
  return get_current_branch(toplevel)
end

local function gh_browse_run(target, opts)
  local toplevel = get_toplevel()
  if not toplevel then return end
  local branch = resolve_branch(opts, toplevel)
  if not branch then return end
  local repo = get_repo_name(toplevel)
  if not repo then return end
  local cmd = "cd " .. vim.fn.shellescape(toplevel) .. " && gh browse --no-browser "
      .. vim.fn.shellescape(target) .. " -b " .. vim.fn.shellescape(branch)
      .. " -R " .. vim.fn.shellescape(repo) .. " 2>&1"
  local out = vim.trim(vim.fn.system(cmd))
  if vim.v.shell_error ~= 0 then
    gh_err("gh browse failed: " .. out)
    return
  end
  -- stdin must be null: on Linux, open -> xdg-open -> $BROWSER (~/.local/bin/opener),
  -- which reads the URL from stdin when it's a pipe, and jobstart's default stdin is one.
  vim.fn.jobstart({ "open", out }, { detach = true, stdin = "null" })
end

local function gh_browse(opts)
  local toplevel = get_toplevel()
  if not toplevel then return end
  local file = get_repo_relative_path(toplevel)
  if not file then return end
  gh_browse_run(file, opts)
end

local function gh_browse_lines(opts)
  local toplevel = get_toplevel()
  if not toplevel then return end
  local file = get_repo_relative_path(toplevel)
  if not file then return end

  local start_line, end_line
  if opts.range > 0 then
    start_line, end_line = opts.line1, opts.line2
  else
    start_line = vim.fn.line(".")
    end_line = start_line
  end

  local target = file .. ":" .. start_line
  if start_line ~= end_line then
    target = target .. "-" .. end_line
  end
  gh_browse_run(target, opts)
end

function M.setup()
  vim.api.nvim_create_user_command("Gho", function() gh_browse({}) end, {})
  vim.api.nvim_create_user_command("Ghom", function() gh_browse({ branch = "default" }) end, {})
  vim.api.nvim_create_user_command("Ghl", function(opts) gh_browse_lines(opts) end, { range = true })
  vim.api.nvim_create_user_command("Ghlm",
    function(opts) gh_browse_lines({ range = opts.range, line1 = opts.line1, line2 = opts.line2, branch = "default" }) end,
    { range = true })
end

return M
