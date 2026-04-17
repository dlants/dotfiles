-- Plugin configuration (called after vim.pack.add loads plugins)

-- Function to temporarily show virtual lines
local function show_virtual_lines_until_next_move()
  vim.diagnostic.config({ virtual_lines = true })
  vim.defer_fn(function()
    vim.api.nvim_create_autocmd("CursorMoved", {
      once = true,
      callback = function()
        vim.diagnostic.config({ virtual_lines = false })
      end
    })
  end, 50)
end

--------------------------------------------------------------------------------
-- magenta.nvim
--------------------------------------------------------------------------------
local magenta_timings = vim.env.MAGENTA_TIMINGS ~= nil
if magenta_timings then
  vim.notify(string.format("[magenta] pre-require: %.3fms", vim.loop.hrtime() / 1e6))
end
local magenta_ok, magenta = pcall(require, "magenta")
if magenta_timings then
  vim.notify(string.format("[magenta] post-require: %.3fms", vim.loop.hrtime() / 1e6))
end
if magenta_ok then
  local magenta_config = require("config.magenta")
  if magenta_timings then
    vim.notify(string.format("[magenta] pre-setup: %.3fms", vim.loop.hrtime() / 1e6))
  end
  magenta.setup({
    profiles = magenta_config.profiles,
    sidebarPosition = "left",
    editPrediction = magenta_config.editPrediction,
    chimeVolume = 0,
  })
  if magenta_timings then
    vim.notify(string.format("[magenta] post-setup: %.3fms", vim.loop.hrtime() / 1e6))
  end
end

--------------------------------------------------------------------------------
-- snacks.nvim
--------------------------------------------------------------------------------
require("snacks").setup({
  input = {},
  indent = {},
  rename = {},
  bigfile = { notify = true },
})

--------------------------------------------------------------------------------
-- fzf-lua
--------------------------------------------------------------------------------
local fzf_lua = require("fzf-lua")
fzf_lua.setup({
  winopts = {
    height = 0.5,
    width = 1.0,
    row = 0,
    border = "none"
  },
  previewers = {
    builtin = {
      extensions = {
        ["png"] = false,
        ["jpg"] = false,
        ["jpeg"] = false,
        ["gif"] = false,
        ["webp"] = false,
      }
    }
  }
})
fzf_lua.register_ui_select()

vim.keymap.set("n", "<leader>F", function()
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  local cwd = vim.v.shell_error == 0 and git_root or nil
  fzf_lua.files({
    fd_opts = "--color=never --type f --hidden --follow --no-ignore",
    cwd = cwd,
  })
end, { desc = "FZF All Files in git root (including gitignored)", silent = true })

vim.keymap.set("n", "<leader>f", function() fzf_lua.files() end, { desc = "FZF Files", silent = true })
vim.keymap.set("n", "<leader>h", function() fzf_lua.helptags() end, { desc = "FZF grep help", silent = true })
vim.keymap.set("n", "<leader>/", function() fzf_lua.live_grep() end, { desc = "FZF live grep", silent = true })
vim.keymap.set("n", "<leader>b", function() fzf_lua.buffers() end, { desc = "FZF buffers", silent = true })
vim.keymap.set("n", "<leader>p", function()
  fzf_lua.files({ cwd = "~/.claude/skills/benchling-knowledgebase/knowledge" })
end, { desc = "Find files in PKB", silent = true })

--------------------------------------------------------------------------------
-- grepper
--------------------------------------------------------------------------------
vim.g.grepper = {
  prompt_quote = 0,
  tools = { "rg" }
}
vim.keymap.set("n", "<leader>g", ":Grepper<CR>", { desc = "Open Grepper", noremap = true, silent = true })

--------------------------------------------------------------------------------
-- oil.nvim
--------------------------------------------------------------------------------
require("oil").setup({
  default_file_explorer = true,
  columns = { "icon" },
  keymaps = {
    ["<C-h>"] = false
  },
  view_options = {
    show_hidden = true
  }
})
vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "oil" })

vim.api.nvim_create_autocmd("User", {
  pattern = "OilActionsPost",
  callback = function(event)
    local action = event.data.actions
    if action.type == "move" then
      require("snacks").rename.on_rename_file(action.src_url, action.dest_url)
      local old_path = vim.fn.fnamemodify(action.src_url:gsub("^oil://", ""), ":p")
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == old_path then
          vim.api.nvim_buf_delete(buf, { force = true })
          break
        end
      end
    elseif action.type == "delete" then
      local deleted_path = vim.fn.fnamemodify(action.url:gsub("^oil://", ""), ":p")
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == deleted_path then
          vim.api.nvim_buf_delete(buf, { force = true })
          break
        end
      end
    end
  end,
})

--------------------------------------------------------------------------------
-- lualine
--------------------------------------------------------------------------------
local function relative_path()
  return vim.fn.expand("%")
end

require("lualine").setup({
  options = {
    icons_enabled = true,
    component_separators = { "", "" },
    section_separators = { "", "" },
    disabled_filetypes = {}
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { { "diagnostics", sources = { "nvim_lsp" } } },
    lualine_c = { relative_path },
    lualine_x = { "filetype" },
    lualine_y = { "branch" },
    lualine_z = { "location" }
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = { relative_path },
    lualine_x = {},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {},
  extensions = {}
})

--------------------------------------------------------------------------------
-- gitsigns
--------------------------------------------------------------------------------
require("gitsigns").setup()

vim.keymap.set('n', ']c', function()
  if vim.wo.diff then return ']c' end
  vim.schedule(function() require('gitsigns').nav_hunk('next') end)
  return '<Ignore>'
end, { expr = true, desc = 'Next git hunk' })

vim.keymap.set('n', '[c', function()
  if vim.wo.diff then return '[c' end
  vim.schedule(function() require('gitsigns').nav_hunk('prev') end)
  return '<Ignore>'
end, { expr = true, desc = 'Previous git hunk' })

--------------------------------------------------------------------------------
-- jj.nvim
--------------------------------------------------------------------------------
require("jj").setup()

--------------------------------------------------------------------------------
-- comment.nvim
--------------------------------------------------------------------------------
require("Comment").setup({})

--------------------------------------------------------------------------------
-- nvim-surround
--------------------------------------------------------------------------------
require("nvim-surround").setup({})

--------------------------------------------------------------------------------
-- nvim-colorizer
--------------------------------------------------------------------------------
require('colorizer').setup({
  filetypes = { '*' },
  user_default_options = {
    RGB = true,
    RRGGBB = true,
    RRGGBBAA = true,
    names = false,
    rgb_fn = false,
    hsl_fn = false,
    css = false,
    css_fn = false,
    mode = 'background',
  },
})

--------------------------------------------------------------------------------
-- fidget.nvim (lazy-load on LspAttach)
--------------------------------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
  once = true,
  callback = function()
    require("fidget").setup({
      text = { spinner = "dots" },
      window = { blend = 0 }
    })
  end
})

--------------------------------------------------------------------------------
-- alabaster (colorscheme)
--------------------------------------------------------------------------------
vim.opt.termguicolors = true
vim.cmd("colorscheme alabaster")
vim.api.nvim_set_hl(0, "@markup.raw.block", { link = "Special" })

--------------------------------------------------------------------------------
-- nvim-lspconfig
--------------------------------------------------------------------------------
vim.diagnostic.config({
  virtual_text = false,
  virtual_lines = false,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true
})

local capabilities = require("cmp_nvim_lsp").default_capabilities()
capabilities.textDocument.completion.completionItem.snippetSupport = true

local on_attach = function(_, bufnr)
  local function buf_set_keymap(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, noremap = true, silent = true })
  end

  buf_set_keymap("n", "<leader>k", vim.lsp.buf.hover)
  buf_set_keymap("n", "gd", vim.lsp.buf.definition)
  buf_set_keymap("n", "gD", vim.lsp.buf.type_definition)
  buf_set_keymap("n", "gi", vim.lsp.buf.implementation)
  buf_set_keymap("n", "gr", vim.lsp.buf.references)
  buf_set_keymap("n", "<leader>r", vim.lsp.buf.rename)
  buf_set_keymap("n", "<leader>x", [[:FzfLua lsp_code_actions<CR>]])
  buf_set_keymap("i", "<C-s>", vim.lsp.buf.signature_help)
  buf_set_keymap("n", "<leader>d", vim.diagnostic.setqflist)
  buf_set_keymap("n", "[d", function()
    vim.diagnostic.jump({ count = -1, float = false })
    show_virtual_lines_until_next_move()
  end)
  buf_set_keymap("n", "]d", function()
    vim.diagnostic.jump({ count = 1, float = false })
    show_virtual_lines_until_next_move()
  end)
  buf_set_keymap("n", "<leader>e", function()
    show_virtual_lines_until_next_move()
  end)
end

local default_config = {
  on_attach = on_attach,
  capabilities = capabilities,
  flags = { debounce_text_changes = 150 }
}

vim.lsp.config("ts_ls", vim.tbl_deep_extend("force", default_config, {
  settings = {
    typescript = {
      inlayHints = {
        includeInlayParameterNameHints = "all",
        includeInlayParameterNameHintsWhenArgumentMatchesName = false,
        includeInlayFunctionParameterTypeHints = true,
        includeInlayVariableTypeHints = true,
        includeInlayPropertyDeclarationTypeHints = true,
        includeInlayFunctionLikeReturnTypeHints = true,
        includeInlayEnumMemberValueHints = true,
      },
      preferences = {
        importModuleSpecifier = "relative"
      }
    }
  }
}))

vim.lsp.config("rust_analyzer", vim.tbl_deep_extend("force", default_config, {
  settings = {
    ["rust-analyzer"] = {
      assist = { importGranularity = "module", importPrefix = "self" },
      cargo = { loadOutDirsFromCheck = true },
      procMacro = { enable = true },
      checkOnSave = { command = "clippy" }
    }
  }
}))

vim.lsp.config("lua_ls", vim.tbl_deep_extend("force", default_config, {
  on_init = function(client)
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if vim.fn.filereadable(path .. "/.luarc.json") or vim.fn.filereadable(path .. "/.luarc.jsonc") then
        return
      end
    end
    client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua, {
      runtime = { version = "LuaJIT" },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } }
    })
  end,
  settings = { Lua = {} }
}))

vim.lsp.config("zls", vim.tbl_deep_extend("force", default_config, {
  settings = { zls = { semantic_tokens = "partial" } }
}))

vim.lsp.config("ty", default_config)
vim.lsp.config("ruff", default_config)
vim.lsp.config("biome", default_config)

for _, server in ipairs({ "bashls", "dockerls", "eslint", "jsonls", "terraformls", "tflint", "yamlls", "teal_ls" }) do
  vim.lsp.config(server, default_config)
end

vim.lsp.enable({
  "bashls", "dockerls", "eslint", "jsonls", "terraformls", "tflint", "yamlls", "teal_ls",
  "ts_ls", "rust_analyzer", "lua_ls", "zls", "ty", "ruff", "biome"
})

--------------------------------------------------------------------------------
-- conform.nvim
--------------------------------------------------------------------------------
require("conform").setup({
  formatters_by_ft = {
    javascript = { "biome", "prettier", stop_after_first = true },
    typescript = { "biome", "prettier", stop_after_first = true },
    javascriptreact = { "biome", "prettier", stop_after_first = true },
    typescriptreact = { "biome", "prettier", stop_after_first = true },
    json = { "biome", "prettier", stop_after_first = true },
    yaml = { "prettier" },
    html = { "prettier" },
    css = { "biome", "prettier", stop_after_first = true },
    scss = { "prettier" },
    markdown = { "prettier" },
    rust = { "rustfmt" },
  },
  format_on_save = {
    timeout_ms = 500,
    lsp_fallback = true,
  },
})

vim.keymap.set({ "n", "v" }, "<leader>`", function()
  require("conform").format({
    lsp_fallback = true,
    async = false,
    timeout_ms = 500,
  })
end, { desc = "Format buffer" })

--------------------------------------------------------------------------------
-- nvim-jdtls (lazy-load on java filetype)
--------------------------------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = "java",
  once = true,
  callback = function()
    local config = {
      settings = { java = {} },
      on_attach = function(_, bufnr)
        local opts = { buffer = bufnr, noremap = true, silent = true }
        vim.keymap.set("n", "<leader>k", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "gD", vim.lsp.buf.type_definition, opts)
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "<leader>x", [[:FzfLua lsp_code_actions<CR>]])
        vim.keymap.set("n", "<leader>d", vim.diagnostic.setqflist)
        vim.keymap.set("n", "[d", function()
          vim.diagnostic.jump({ count = -1, float = false })
          show_virtual_lines_until_next_move()
        end)
        vim.keymap.set("n", "]d", function()
          vim.diagnostic.jump({ count = 1, float = false })
          show_virtual_lines_until_next_move()
        end)
        vim.keymap.set("n", "<leader>e", function()
          show_virtual_lines_until_next_move()
        end)
        vim.keymap.set("n", "<leader>`", function()
          vim.lsp.buf.format({ async = true })
        end, opts)
      end
    }
    vim.lsp.config("jdtls", config)
    vim.lsp.enable("jdtls")
  end
})

--------------------------------------------------------------------------------
-- nvim-cmp
--------------------------------------------------------------------------------
local cmp = require("cmp")
vim.opt.completeopt = { "menu", "menuone", "noselect" }

local lspkind = require("lspkind")
lspkind.init({ symbol_map = { Supermaven = "" } })

local kind_formatter = lspkind.cmp_format({
  mode = "symbol_text",
  menu = {
    buffer = "[buf]",
    nvim_lsp = "[LSP]",
    nvim_lua = "[api]",
    path = "[path]",
    gh_issues = "[issues]",
    supermaven = "[AI]"
  }
})

cmp.setup({
  formatting = {
    fields = { "abbr", "kind", "menu" },
    expandable_indicator = true,
    format = kind_formatter
  },
  mapping = {
    ["<CR>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.confirm({ select = true, behavior = cmp.SelectBehavior.Insert })
      else
        fallback()
      end
    end, { "i", "c" }),
    ["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then cmp.select_next_item() else fallback() end
    end, { "i", "s" }),
    ["<S-Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then cmp.select_prev_item() else fallback() end
    end, { "i", "s" }),
    ["<C-j>"] = cmp.mapping(function(fallback)
      if cmp.visible() then cmp.select_next_item() else fallback() end
    end, { "i", "s" }),
    ["<C-k>"] = cmp.mapping(function(fallback)
      if cmp.visible() then cmp.select_prev_item() else fallback() end
    end, { "i", "s" })
  },
  sources = {
    { name = "nvim_lsp" },
    { name = "path" },
    {
      name = "buffer",
      option = {
        get_bufnrs = function()
          local bufs = {}
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            bufs[vim.api.nvim_win_get_buf(win)] = true
          end
          return vim.tbl_keys(bufs)
        end
      }
    }
  }
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "lua",
  callback = function()
    cmp.setup.buffer({
      sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "nvim_lua" },
        { name = "path" },
        {
          name = "buffer",
          option = {
            get_bufnrs = function()
              local bufs = {}
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                bufs[vim.api.nvim_win_get_buf(win)] = true
              end
              return vim.tbl_keys(bufs)
            end
          }
        }
      })
    })
  end
})

--------------------------------------------------------------------------------
-- nvim-notify
--------------------------------------------------------------------------------
vim.notify = require("notify")

--------------------------------------------------------------------------------
-- leap.nvim
--------------------------------------------------------------------------------
local leap = require("leap")
vim.keymap.set({ "n", "x", "o" }, "s", function()
  leap.leap({ target_windows = { vim.fn.win_getid() } })
end, { silent = true, desc = "leap forward or backward" })

--------------------------------------------------------------------------------
-- treesitter
--------------------------------------------------------------------------------
require("nvim-treesitter").setup({
  install_dir = vim.fn.stdpath('data') .. '/site'
})

local ensure_installed = {
  "lua", "typescript", "tsx", "javascript", "json", "yaml", "html", "css",
  "rust", "bash", "markdown", "markdown_inline", "teal", "python", "nix",
  "vim", "vimdoc", "toml", "terraform", "java", "zig", "query", "regex",
}

local installed = require('nvim-treesitter.config').get_installed()
local to_install = vim.iter(ensure_installed)
    :filter(function(lang) return not vim.tbl_contains(installed, lang) end)
    :totable()
if #to_install > 0 then
  require('nvim-treesitter').install(to_install)
end

local ts_filetypes = {
  "lua", "typescript", "tsx", "javascript", "typescriptreact", "javascriptreact",
  "json", "yaml", "html", "css", "rust", "bash", "markdown", "teal"
}

vim.api.nvim_create_autocmd('FileType', {
  pattern = ts_filetypes,
  callback = function(args)
    local max_filesize = 100 * 1024
    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
    if ok and stats and stats.size > max_filesize then return end
    vim.treesitter.start()
  end,
})

--------------------------------------------------------------------------------
-- treesitter-context
--------------------------------------------------------------------------------
require("treesitter-context").setup({ enable = true })

--------------------------------------------------------------------------------
-- treesitter-textobjects
--------------------------------------------------------------------------------
require("nvim-treesitter-textobjects").setup({
  select = { lookahead = true },
  move = { set_jumps = true },
})

local ts_select = require("nvim-treesitter-textobjects.select")
local ts_move = require("nvim-treesitter-textobjects.move")

local select_maps = {
  ["af"] = "@function.outer",
  ["if"] = "@function.inner",
  ["ac"] = "@class.outer",
  ["ic"] = "@class.inner",
  ["aa"] = "@parameter.outer",
  ["ia"] = "@parameter.inner",
}
for key, query in pairs(select_maps) do
  vim.keymap.set({ "x", "o" }, key, function()
    ts_select.select_textobject(query, "textobjects")
  end)
end

vim.keymap.set({ "n", "x", "o" }, "]f", function()
  ts_move.goto_next_start("@function.outer", "textobjects")
end)
vim.keymap.set({ "n", "x", "o" }, "[f", function()
  ts_move.goto_previous_start("@function.outer", "textobjects")
end)
vim.keymap.set({ "n", "x", "o" }, "]F", function()
  ts_move.goto_next_end("@function.outer", "textobjects")
end)
vim.keymap.set({ "n", "x", "o" }, "[F", function()
  ts_move.goto_previous_end("@function.outer", "textobjects")
end)
vim.keymap.set({ "n", "x", "o" }, "]a", function()
  ts_move.goto_next_start("@parameter.inner", "textobjects")
end)
vim.keymap.set({ "n", "x", "o" }, "[a", function()
  ts_move.goto_previous_start("@parameter.inner", "textobjects")
end)
