require("harpoon").setup(
  {
    mark_branch = true
  }
)

vim.api.nvim_set_keymap(
  "",
  "<leader>h",
  [[<Cmd>lua require('harpoon.mark').add_file()<CR>]],
  {noremap = true, silent = true}
)

-- s to match the session selector window in tmux
vim.api.nvim_set_keymap(
  "",
  "<leader>s",
  [[<Cmd>lua require('harpoon.ui').toggle_quick_menu()<CR>]],
  {noremap = true, silent = true}
)

for i = 1, 5, 1 do
  vim.api.nvim_set_keymap(
    "",
    "<leader>h" .. i,
    [[<Cmd>lua require('harpoon.mark').set_current_at(]] .. i .. [[)<CR>]],
    {noremap = true, silent = true}
  )

  vim.api.nvim_set_keymap(
    "",
    "<leader>" .. i,
    [[<Cmd>lua require('harpoon.ui').nav_file(]] .. i .. [[)<CR>]],
    {noremap = true, silent = true}
  )
end
