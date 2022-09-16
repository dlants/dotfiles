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


require('telescope').setup {
  defaults = {
    layout_strategy = 'horizontal',
    layout_config = {
      height = 0.5,
      width = 0.9,
      anchor = 'N'
    },

    mappings = {
      i = {
        ["<C-j>"] = require('telescope.actions').move_selection_next,
        ["<C-k>"] = require('telescope.actions').move_selection_previous
      }
    },
  },

  extensions = {
    fzf = {
      fuzzy = true,                    -- false will only do exact matching
      override_generic_sorter = true,  -- override the generic sorter
      override_file_sorter = true,     -- override the file sorter
      case_mode = "smart_case",        -- or "ignore_case" or "respect_case"
    }
  }
}

-- To get fzf loaded and working with telescope, you need to call
-- load_extension, somewhere after setup function:
require('telescope').load_extension('fzf')

-- vim.api.nvim_set_keymap(
--   "n",
--   "<leader>g",
--   [[<cmd>lua require('telescope.builtin').live_grep()<CR>]],
--   {noremap = true, silent = true}
-- )
