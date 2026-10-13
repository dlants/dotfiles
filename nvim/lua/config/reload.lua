-- Hot-reload for config modules: each module must expose an idempotent
-- setup() (augroups with clear = true, commands/keymaps overwrite). Every
-- running nvim polls the module files' mtime, so saving a file from any
-- nvim re-applies it everywhere.
local M = {}

local POLL_MS = 1000
local pollers = {}

local function module_path(name)
  return vim.api.nvim_get_runtime_file("lua/" .. name:gsub("%.", "/") .. ".lua", false)[1]
end

function M.reload(name)
  package.loaded[name] = nil
  local ok, err = pcall(function() require(name).setup() end)
  if not ok then
    vim.notify("reload " .. name .. " failed: " .. err, vim.log.levels.ERROR)
  end
end

function M.watch(names)
  for _, name in ipairs(names) do
    require(name).setup()
    local path = module_path(name)
    if path and not pollers[name] then
      local poller = vim.uv.new_fs_poll()
      poller:start(path, POLL_MS, vim.schedule_wrap(function(err)
        if not err then M.reload(name) end
      end))
      pollers[name] = poller
    end
  end
end

return M
