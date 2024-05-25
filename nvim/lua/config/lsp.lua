local lsp = require "lspconfig"

-- on_attach only maps when the language server attaches to the current buffer
local on_attach = function(client, bufnr)
  local opts = {noremap = true, silent = true}
  local function buf_set_keymap(...)
    vim.api.nvim_buf_set_keymap(bufnr, ...)
  end

  buf_set_keymap("n", "<leader>t", [[<Cmd>lua vim.lsp.buf.hover()<CR>]], opts)
  buf_set_keymap("n", "<leader>d", [[<Cmd>lua vim.lsp.buf.definition()<CR>]], opts)
  buf_set_keymap("n", "<leader>D", [[<Cmd>lua vim.lsp.buf.declaration()<CR>]], opts)
  buf_set_keymap("n", "<leader>r", [[<Cmd>lua vim.lsp.buf.references()<CR>]], opts)
  buf_set_keymap("n", "<leader>R", [[<Cmd>lua vim.lsp.buf.rename()<CR>]], opts)
  -- buf_set_keymap('n', '<leader>`', [[<Cmd>lua vim.lsp.buf.formatting_sync()<CR>]], opts)

  buf_set_keymap("n", "<leader>i", [[<Cmd>lua vim.diagnostic.setloclist()<CR>]], opts)
  buf_set_keymap("n", "[e", [[<Cmd>lua vim.diagnostic.goto_prev()<CR>]], opts)
  buf_set_keymap("n", "]e", [[<Cmd>lua vim.diagnostic.goto_next()<CR>]], opts)
  buf_set_keymap("n", "<leader>f", [[<Cmd>lua vim.lsp.buf.format({async=true})<CR>]], opts)

  require "lsp_signature".on_attach {
    bind = true,
    hint_prefix = "",
    handler_opts = {
      border = "none"
    }
  }
end

local servers = {"dockerls", "bashls", "jsonls", "terraformls", "tflint", "eslint", "yamlls"}
for _, server in ipairs(servers) do
  lsp[server].setup {
    on_attach = on_attach,
    flags = {
      debounce_text_changes = 150
    },
    capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
  }
end

lsp.tsserver.setup {
  -- cmd = {"typescript-language-server", "--stdio", "--log-level", "4"},
  init_options = {
    hostInfo = "neovim",
    maxTsServerMemory = 4096,
    -- tsserver = {
    --   logDirectory = "/Users/denislantsman/.local/state/nvim/",
    --   logVerbosity = "verbose"
    -- }
  },
  on_attach = on_attach,
  flags = {
    debounce_text_changes = 150
  },
  capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
}

-- lsp.tflint.setup{}
-- vim.api.nvim_create_autocmd({"BufWritePre"}, {
--   pattern = {"*.tf", "*.tfvars"},
--   callback = vim.lsp.buf.format,
-- })

lsp.rust_analyzer.setup(
  {
    on_attach = on_attach,
    settings = {
      ["rust-analyzer"] = {
        assist = {
          importGranularity = "module",
          importPrefix = "self"
        },
        cargo = {
          loadOutDirsFromCheck = true
        },
        procMacro = {
          enable = true
        }
      }
    }
  }
)

-- local system_name
-- if vim.fn.has("mac") == 1 then
--   system_name = "macOS"
-- elseif vim.fn.has("unix") == 1 then
--   system_name = "Linux"
-- elseif vim.fn.has("win32") == 1 then
--   system_name = "Windows"
-- else
--   print("Unsupported system for sumneko")
-- end
--
-- -- set the path to the sumneko installation; if you previously installed via the now deprecated :LspInstall, use
-- local sumneko_root_path = "/Users/dlants/src/lua-language-server"
-- local sumneko_binary = sumneko_root_path .. "/bin/" .. system_name .. "/lua-language-server"
--
-- local runtime_path = vim.split(package.path, ";")
-- table.insert(runtime_path, "lua/?.lua")
-- table.insert(runtime_path, "lua/?/init.lua")
--
-- lsp.sumneko_lua.setup {
--   cmd = {sumneko_binary, "-E", sumneko_root_path .. "/main.lua"},
--   on_attach = on_attach,
--   settings = {
--     Lua = {
--       runtime = {
--         -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
--         version = "LuaJIT",
--         -- Setup your lua path
--         path = runtime_path
--       },
--       diagnostics = {
--         -- Get the language server to recognize the `vim` global
--         globals = {"vim"}
--       },
--       workspace = {
--         -- Make the server aware of Neovim runtime files
--         library = vim.api.nvim_get_runtime_file("", true)
--       },
--       -- Do not send telemetry data containing a randomized but unique identifier
--       telemetry = {
--         enable = false
--       }
--     }
--   }
-- }

-- on_attach only maps when the language server attaches to the current buffer
-- local on_attach_jdt = function(client, bufnr)
--   local opts = {noremap = true, silent = true}
--   local function buf_set_keymap(...)
--     vim.api.nvim_buf_set_keymap(bufnr, ...)
--   end
--
--   buf_set_keymap("n", "<leader>t", [[<Cmd>lua vim.lsp.buf.hover()<CR>]], opts)
--   buf_set_keymap("n", "<leader>d", [[<Cmd>lua vim.lsp.buf.definition()<CR>]], opts)
--   buf_set_keymap("n", "<leader>D", [[<Cmd>lua vim.lsp.buf.declaration()<CR>]], opts)
--   buf_set_keymap("n", "<leader>r", [[<Cmd>lua vim.lsp.buf.references()<CR>]], opts)
--   buf_set_keymap("n", "<leader>R", [[<Cmd>lua vim.lsp.buf.rename()<CR>]], opts)
--   -- buf_set_keymap('n', '<leader>`', [[<Cmd>lua vim.lsp.buf.formatting_sync()<CR>]], opts)
--
--   buf_set_keymap("n", "<leader>i", [[<Cmd>lua vim.diagnostic.setloclist()<CR>]], opts)
--   buf_set_keymap("n", "[e", [[<Cmd>lua vim.diagnostic.goto_prev()<CR>]], opts)
--   buf_set_keymap("n", "]e", [[<Cmd>lua vim.diagnostic.goto_next()<CR>]], opts)
--
--   require "lsp_signature".on_attach {
--     bind = true,
--     hint_prefix = "",
--     handler_opts = {
--       border = "none"
--     }
--   }
-- end

-- borrows from https://github.com/mfussenegger/dotfiles/blob/89a0acc43ac1d8c2ee475a00b8a448a23b8c1c26/vim/.config/nvim/lua/lsp-config.lua#L126-L196
-- function M.start_jdt()
--   print("start_jdt")
--   local root_markers = {"gradlew", ".git"}
--   local root_dir = require("jdtls.setup").find_root(root_markers)
--   local home = os.getenv("HOME")
--   local workspace_folder = home .. "/.local/share/eclipse/" .. vim.fn.fnamemodify(root_dir, ":p:h:t")
--
--   -- from https://github.com/mfussenegger/nvim-jdtls readme
--   local config = {
--     cmd = {
--       "java",
--       "-Declipse.application=org.eclipse.jdt.ls.core.id1",
--       "-Dosgi.bundles.defaultStartLevel=4",
--       "-Declipse.product=org.eclipse.jdt.ls.core.product",
--       "-Dlog.protocol=true",
--       "-Dlog.level=ALL",
--       "-Xms1g",
--       "--add-modules=ALL-SYSTEM",
--       "--add-opens",
--       "java.base/java.util=ALL-UNNAMED",
--       "--add-opens",
--       "java.base/java.lang=ALL-UNNAMED",
--       "-jar",
--       "/usr/local/Cellar/jdtls/1.9.0-202203031534/libexec/plugins/org.eclipse.equinox.launcher_1.6.400.v20210924-0641.jar",
--       "-configuration",
--       "/usr/local/Cellar/jdtls/1.9.0-202203031534/libexec/config_mac",
--       "-data",
--       workspace_folder
--     },
--     root_dir = require("jdtls.setup").find_root({".git", "mvnw", "gradlew"}),
--     settings = {
--       java = {}
--     },
--     on_attach = on_attach_jdt
--   }
--
--   -- This starts a new client & server,
--   -- or attaches to an existing client & server depending on the `root_dir`.
--   require("jdtls").start_or_attach(config)
-- end
-- return M
