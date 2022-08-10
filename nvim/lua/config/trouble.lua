require("trouble").setup {}

vim.api.nvim_set_keymap("n", "<leader>xx", "<cmd>Trouble<cr>", {silent = true, noremap = true})
vim.api.nvim_set_keymap("n", "<leader>xw", "<cmd>Trouble workspace_diagnostics<cr>", {silent = true, noremap = true})
vim.api.nvim_set_keymap("n", "<leader>xd", "<cmd>Trouble document_diagnostics<cr>", {silent = true, noremap = true})
vim.api.nvim_set_keymap("n", "<leader>xl", "<cmd>Trouble loclist<cr>", {silent = true, noremap = true})
vim.api.nvim_set_keymap("n", "<leader>xq", "<cmd>Trouble quickfix<cr>", {silent = true, noremap = true})
vim.api.nvim_set_keymap("n", "gR", "<cmd>Trouble lsp_references<cr>", {silent = true, noremap = true})

vim.api.nvim_set_keymap(
  "n",
  "]t",
  [[<Cmd>lua require("trouble").next({skip_groups = true, jump = true})<CR>]],
  {silent = true, noremap = true}
)

vim.api.nvim_set_keymap(
  "n",
  "[t",
  [[<Cmd>lua require("trouble").previous({skip_groups = true, jump = true})<CR>]],
  {silent = true, noremap = true}
)
