-- note, requires prettier to be installed globally
-- npm install -g prettier
require "formatter".setup {
  filetype = {
    typescriptreact = {
      function()
        return {
          exe = "npx prettier",
          args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
          stdin = true
        }
      end
    },
    typescript = {
      function()
        return {
          exe = "npx prettier",
          args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
          stdin = true
        }
      end
      -- linter
      -- function()
      --   return {
      --     exe = "eslint",
      --     args = {
      --       "--stdin-filename",
      --       vim.api.nvim_buf_get_name(0),
      --       "--fix",
      --       "--cache"
      --     },
      --     stdin = false
      --   }
      -- end
    },
    javascript = {
      function()
        return {
          exe = "npx prettier",
          args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
          stdin = true
        }
      end
    },
    javascriptreact = {
      function()
        return {
          exe = "npx prettier",
          args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
          stdin = true
        }
      end
    },
    json = {
      function()
        return {
          exe = "npx prettier",
          args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
          stdin = true
        }
      end
    },
    lua = {
      -- luafmt
      function()
        return {
          exe = "luafmt",
          args = {"--indent-count", 2, "--stdin"},
          stdin = true
        }
      end
    }
  }
}

vim.api.nvim_set_keymap("n", "<leader>`", ":Format<CR>", {noremap = true})
