require("nvim-tree").setup()

vim.api.nvim_set_keymap("n", "<leader>-", ":NvimTreeFindFile<CR>", {noremap = true})
