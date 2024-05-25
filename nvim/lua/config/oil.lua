-- from https://github.com/stevearc/oil.nvim?tab=readme-ov-file#quick-start
require("oil").setup({
  default_file_explorer = true,
  columns = { "icon", },
  keymaps = {
    ["<C-h>"] = false
  },
  view_options = {
    show_hidden = true
  }
})

vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
