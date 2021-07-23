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

  buf_set_keymap("n", "<leader>i", [[<Cmd>lua vim.lsp.diagnostic.set_loclist()<CR>]], opts)
  buf_set_keymap("n", "[e", [[<Cmd>lua vim.lsp.diagnostic.goto_prev()<CR>]], opts)
  buf_set_keymap("n", "]e", [[<Cmd>lua vim.lsp.diagnostic.goto_next()<CR>]], opts)

  require "lsp_signature".on_attach {
    bind=true,
    hint_prefix="",
    handler_opts={
      border="none"
    }
  }
end

local servers = {"tsserver", "dockerls", "bashls", "jsonls"}
for _, server in ipairs(servers) do
  lsp[server].setup {
    on_attach = on_attach,
    flags = {
      debounce_text_changes = 150
    }
  }
end

local system_name
if vim.fn.has("mac") == 1 then
  system_name = "macOS"
elseif vim.fn.has("unix") == 1 then
  system_name = "Linux"
elseif vim.fn.has("win32") == 1 then
  system_name = "Windows"
else
  print("Unsupported system for sumneko")
end

-- set the path to the sumneko installation; if you previously installed via the now deprecated :LspInstall, use
local sumneko_root_path = "/Users/dlants/src/lua-language-server"
local sumneko_binary = sumneko_root_path .. "/bin/" .. system_name .. "/lua-language-server"

local runtime_path = vim.split(package.path, ";")
table.insert(runtime_path, "lua/?.lua")
table.insert(runtime_path, "lua/?/init.lua")

lsp.sumneko_lua.setup {
  cmd = {sumneko_binary, "-E", sumneko_root_path .. "/main.lua"},
  on_attach = on_attach,
  settings = {
    Lua = {
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = "LuaJIT",
        -- Setup your lua path
        path = runtime_path
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = {"vim"}
      },
      workspace = {
        -- Make the server aware of Neovim runtime files
        library = vim.api.nvim_get_runtime_file("", true)
      },
      -- Do not send telemetry data containing a randomized but unique identifier
      telemetry = {
        enable = false
      }
    }
  }
}
