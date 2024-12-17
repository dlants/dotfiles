local root = vim.fn.fnamemodify("./.repro", ":p")

-- set stdpaths to use .repro
for _, name in ipairs {"config", "data", "state", "cache"} do
  vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

-- bootstrap lazy
local lazypath = root .. "/plugins/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system {
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath
  }
end
vim.opt.runtimepath:prepend(lazypath)

-- install plugins
local plugins = {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {"nvim-telescope/telescope-fzf-native.nvim", build = "make"}
    },
    keys = {
      {
        "<space>h",
        function()
          require("telescope.builtin").help_tags()
        end,
        desc = "Help Tags"
      }
    },
    config = function()
      -- ADD INIT.LUA SETTINGS THAT ARE _NECESSARY_ FOR REPRODUCING THE ISSUE
      telescope = require("telescope")
      telescope.setup {
        defaults = {
          path_display = {"truncate"},
          sorting_strategy = "ascending",
          layout_config = {
            horizontal = {
              prompt_position = "top"
            }
          },
          mappings = {
            i = {
              ["<C-h>"] = "which_key",
              ["<C-u>"] = false,
              ["<C-d>"] = false
            }
          },
          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case"
          }
        },
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case"
          }
        },
        pickers = {
          lsp_code_actions = {
            theme = "dropdown"
          },
          find_files = {
            find_command = {"rg", "--files", "--hidden", "--glob", "!**/.git/*"}
          }
        }
      }
      telescope.load_extension("fzf")
    end
  }
}

require("lazy").setup(
  plugins,
  {
    root = root .. "/plugins"
  }
)
