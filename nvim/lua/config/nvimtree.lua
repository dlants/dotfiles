-- from https://github.com/nvim-tree/nvim-tree.lua#custom-mappings
local function my_on_attach(bufnr)
  local api = require "nvim-tree.api"

  local function opts(desc)
    return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
  end

  -- default mappings
  api.config.mappings.default_on_attach(bufnr)

  -- custom mappings
  vim.keymap.set("n", "+", ":NvimTreeResize +20<CR>", opts('Resize +'))
  vim.keymap.set("n", "-", ":NvimTreeResize -20<CR>", opts('Resize -'))
end

vim.api.nvim_set_keymap("n", "<leader>-", ":NvimTreeFindFileToggle<CR>", {noremap = true})

require("nvim-tree").setup({
  view = {
    width = 50,
  },
  on_attach = my_on_attach,
})
