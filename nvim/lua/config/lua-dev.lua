
local lspconfig = require("lspconfig")
local luadev = require("lua-dev").setup({
  cmd= {}
})
lspconfig.sumneko_lua.setup(luadev)
