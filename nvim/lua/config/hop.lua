vim.api.nvim_set_keymap(
  "",
  "<leader>f",
  [[<Cmd>lua require('hop').hint_char1({direction=2})<CR>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  "",
  "<leader>F",
  [[<Cmd>lua require('hop').hint_char1({direction=1})<CR>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  "",
  "<leader>w",
  [[<Cmd>lua require('hop').hint_words({direction=2})<CR>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  "",
  "<leader>b",
  [[<Cmd>lua require('hop').hint_words({direction=1})<CR>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  "",
  "<leader>j",
  [[<Cmd>lua require('hop').hint_lines_skip_whitespace({direction=2})<CR>]],
  {noremap = true, silent = true}
)
vim.api.nvim_set_keymap(
  "",
  "<leader>k",
  [[<Cmd>lua require('hop').hint_lines_skip_whitespace({direction=1})<CR>]],
  {noremap = true, silent = true}
)

vim.api.nvim_set_keymap("", "<leader>/", [[<Cmd>lua require('hop').hint_pattern()<CR>]], {noremap = true, silent = true})
vim.api.nvim_set_keymap("", "s", [[<Cmd>lua require('hop').hint_char1()<CR>]], {noremap = true, silent = true})
vim.api.nvim_set_keymap("", "S", [[<Cmd>lua require('hop').hint_char2()<CR>]], {noremap = true, silent = true})
