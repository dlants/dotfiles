-- Treesitter
require "nvim-treesitter.configs".setup {
  highlight = {
    enable = true
  },
  indent = {
    enable = true
  },
  -- playground = {
  --   enable = true,
  --   disable = {},
  --   updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
  --   persist_queries = false, -- Whether the query persists across vim sessions
  --   keybindings = {
  --     toggle_query_editor = "o",
  --     toggle_hl_groups = "i",
  --     toggle_injected_languages = "t",
  --     toggle_anonymous_nodes = "a",
  --     toggle_language_display = "I",
  --     focus_language = "f",
  --     unfocus_language = "F",
  --     update = "<leader>R",
  --     goto_node = "<cr>",
  --     show_help = "?"
  --   }
  -- },
  -- textobjects = {
  --   select = {
  --     enable = true,
  --     lookahead = true,
  --     keymaps = {
  --       ["ac"] = "@class.outer",
  --       ["ic"] = "@class.inner",
  --       ["af"] = "@function.outer",
  --       ["if"] = "@function.inner",
  --       ["ip"] = "@parameter.inner",
  --       ["ap"] = "@parameter.inner",
  --       ["as"] = "@statement.outer",
  --       ["ab"] = "@block.outer",
  --     }
  --   },
  --   move = {
  --     enable = true,
  --     set_jumps = true,
  --     goto_next_start = {
  --       ["]c"] = "@class.outer",
  --       ["]f"] = "@function.outer",
  --       ["]p"] = "@parameter.inner",
  --       ["]s"] = "@statement.outer",
  --       ["]b"] = "@block.outer"
  --     },
  --     goto_next_end = {
  --       ["]F"] = "@function.outer",
  --       ["]C"] = "@class.outer"
  --     },
  --     goto_previous_start = {
  --       ["[c"] = "@class.outer",
  --       ["[f"] = "@function.outer",
  --       ["[p"] = "@parameter.inner",
  --       ["[s"] = "@statement.outer",
  --       ["[b"] = "@block.outer"
  --     },
  --     goto_previous_end = {
  --       ["[F"] = "@function.outer",
  --       ["[C"] = "@class.outer"
  --     }
  --   }
  -- }
}

require"treesitter-context".setup {
}
