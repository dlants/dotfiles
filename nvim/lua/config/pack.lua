-- Native vim.pack plugin management (Neovim 0.12+)

-- Plugins authored locally and published on GitHub. On Linux they are fetched
-- from GitHub via vim.pack (see below); elsewhere they load from ~/src so local
-- edits take effect immediately.
local is_linux = vim.uv.os_uname().sysname == "Linux"
local local_plugins = { "magenta.nvim", "needle", "shuck", "glean" }
if not is_linux then
  for _, name in ipairs(local_plugins) do
    local path = vim.fn.expand("~/src/" .. name)
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.rtp:prepend(path)
      if vim.fn.isdirectory(path .. "/after") == 1 then
        vim.opt.rtp:append(path .. "/after")
      end
      if vim.fn.isdirectory(path .. "/doc") == 1 then
        vim.cmd("silent! helptags " .. vim.fn.fnameescape(path .. "/doc"))
      end
    end
  end
end

vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if name == "nvim-treesitter" and kind == "update" then
      if not ev.data.active then
        vim.cmd.packadd("nvim-treesitter")
      end
      vim.cmd("TSUpdate")
    end
    if name == "magenta" and (kind == "install" or kind == "update") then
      vim.system({ "npm", "run", "build" }, { cwd = ev.data.path }):wait()
      -- The magenta-scripts packages depend on the SDK shipped with magenta, so
      -- reinstall their runtime deps whenever magenta itself changes.
      local scripts_dir = vim.fn.expand("~/src/dotfiles/magenta-scripts")
      for _, pkg in ipairs(vim.fn.glob(scripts_dir .. "/*/package.json", true, true)) do
        local cwd = vim.fn.fnamemodify(pkg, ":h")
        vim.system({ "npm", "install", "--omit=dev", "--no-audit", "--no-fund" }, { cwd = cwd }):wait()
      end
    end
  end
})

-- Remote plugins managed by vim.pack
vim.pack.add({
  "https://github.com/folke/snacks.nvim",
  "https://github.com/ntpeters/vim-better-whitespace",
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/stevearc/oil.nvim",
  "https://github.com/hoob3rt/lualine.nvim",
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/lewis6991/gitsigns.nvim",
  "https://github.com/tpope/vim-fugitive",
  "https://github.com/numtostr/comment.nvim",
  "https://github.com/kylechui/nvim-surround",
  { src = "https://github.com/catgoose/nvim-colorizer.lua",       name = "catgoose-nvim-colorizer" },
  "https://github.com/j-hui/fidget.nvim",
  "https://github.com/p00f/alabaster.nvim",
  "https://github.com/neovim/nvim-lspconfig",
  "https://github.com/stevearc/conform.nvim",
  "https://github.com/mfussenegger/nvim-jdtls",
  "https://github.com/onsails/lspkind.nvim",
  -- cmp plugins (replaced by blink.cmp, kept for reference)
  -- "https://github.com/hrsh7th/nvim-cmp",
  -- "https://github.com/hrsh7th/cmp-nvim-lsp",
  -- "https://github.com/hrsh7th/cmp-buffer",
  -- "https://github.com/hrsh7th/cmp-nvim-lua",
  -- "https://github.com/hrsh7th/cmp-path",
  -- "https://github.com/hrsh7th/cmp-cmdline",
  { src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1") },
  "https://github.com/rcarriga/nvim-notify",
  "https://codeberg.org/andyg/leap.nvim",
  "https://github.com/neovim-treesitter/treesitter-parser-registry",
  { src = "https://github.com/neovim-treesitter/nvim-treesitter", version = "main" },
  "https://github.com/nvim-treesitter/nvim-treesitter-context",
  { src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects", version = "main" },
  "https://github.com/hashivim/vim-terraform",
})

if is_linux then
  vim.pack.add({
    { src = "https://github.com/dlants/magenta.nvim", name = "magenta" },
    "https://github.com/dlants/needle",
    "https://github.com/dlants/shuck",
    "https://github.com/dlants/glean",
  })
end

-- :PluginUpdate — fetch + show confirmation buffer for all managed plugins
vim.api.nvim_create_user_command("PluginUpdate", function()
  vim.pack.update()
end, {})

-- :PluginClean — remove installed plugins not added via vim.pack.add() this session
vim.api.nvim_create_user_command("PluginClean", function()
  local unused = {}
  for _, p in ipairs(vim.pack.get()) do
    if not p.active then
      table.insert(unused, p.spec.name)
    end
  end
  if #unused == 0 then
    vim.notify("No unused plugins to clean", vim.log.levels.INFO)
    return
  end
  vim.ui.select({ "yes", "no" }, {
    prompt = "Delete " .. #unused .. " unused plugin(s): " .. table.concat(unused, ", "),
  }, function(choice)
    if choice == "yes" then
      vim.pack.del(unused)
    end
  end)
end, {})
