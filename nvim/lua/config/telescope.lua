require "telescope".setup {}

vim.api.nvim_set_keymap(
  "n",
  "<leader>p",
  [[<cmd>lua require('telescope.builtin').find_files()<CR>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  "n",
  "<leader>o",
  [[<cmd>lua require('telescope.builtin').find_files{find_command={'rg', '--files', '-u'}}<CR>]],
  {noremap = true, silent = true}
)

-- vim.api.nvim_set_keymap(
--   "n",
--   "<leader>g",
--   [[<cmd>lua require('telescope.builtin').live_grep()<CR>]],
--   {noremap = true, silent = true}
-- )
