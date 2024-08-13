-- Packer.nvim
-- Bootstrap Packer.nvim if it doesn't exist
local install_path = vim.fn.stdpath("data") .. "/site/pack/packer/opt/packer.nvim"
if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
  vim.fn.system({"git", "clone", "https://github.com/wbthomason/packer.nvim", install_path})
  vim.api.nvim_command "packadd packer.nvim"
end
vim.cmd [[packadd packer.nvim]]
vim.cmd "autocmd BufWritePost plugins.lua PackerCompile"

require("packer").startup(
  {
    function(use)
      -- Let Packer manage itself
      use {"wbthomason/packer.nvim", opt = true}

      -- Make it easier to navigate between tmux and vim panes
      use "christoomey/vim-tmux-navigator"

      -- Trim whitespace on save
      use "ntpeters/vim-better-whitespace"

      -- navigation / grep
      -- use {"junegunn/fzf.vim", requires = {"junegunn/fzf", run = ":call fzf#install()"}}
      -- required by fzf-lua
      use {"junegunn/fzf", run = "./install --bin"}
      -- use {"nvim-telescope/telescope-fzf-native.nvim", run = "make"}
      -- use {
      --   "nvim-telescope/telescope.nvim",
      --   tag = "0.1.0",
      --   -- or                            , branch = '0.1.x',
      --   requires = {{"nvim-lua/plenary.nvim"}}
      -- }
      use {
        "ibhagwan/fzf-lua",
        -- optional for icon support
        requires = {"nvim-tree/nvim-web-devicons"},
        config = function()
          require "fzf-lua".setup({"default"})
        end
      }
      use "ThePrimeagen/harpoon"

      -- grep
      use "mhinz/vim-grepper"

      -- navigation
      -- use {
      --   "nvim-tree/nvim-tree.lua",
      --   requires = {"nvim-tree/nvim-web-devicons"}
      -- }
      use {
        "stevearc/oil.nvim",
        requires = {"nvim-tree/nvim-web-devicons"}
      }

      -- For statusline
      use {
        "hoob3rt/lualine.nvim",
        requires = {"kyazdani42/nvim-web-devicons", opt = true}
      }

      -- Git
      -- use "mhinz/vim-signify"
      use {
        "lewis6991/gitsigns.nvim",
        requires = {
          "nvim-lua/plenary.nvim"
        },
        config = function()
          require("gitsigns").setup()
        end
      }
      use "tpope/vim-fugitive"
      use {
        "pwntester/octo.nvim",
        requires = {
          "nvim-lua/plenary.nvim",
          "nvim-telescope/telescope.nvim",
          "nvim-tree/nvim-web-devicons"
        },
        config = function()
          require "octo".setup(
            {
              picker = "fzf-lua"
            }
          )
        end
      }

      -- quickly jump to file in github from nvim
      use "almo7aya/openingh.nvim"

      use "tpope/vim-rhubarb"

      -- vim enhancements (motion, repeatability)
      -- use "tpope/vim-commentary"
      use {
        "numToStr/Comment.nvim",
        config = function()
          require("Comment").setup()
        end
      }
      -- use "tpope/vim-unimpaired"
      use "tpope/vim-abolish"

      -- incompatible w/ compe
      -- use { 'tpope/vim-endwise' }
      -- use "tpope/vim-repeat"
      use "tpope/vim-surround"

      -- Neovim motions on speed!
      use {
        "smoka7/hop.nvim",
        tag = "*", -- optional but strongly recommended
        config = function()
          -- you can configure Hop the way you like here; see :h hop-config
          require "hop".setup {keys = "etovxqpdygfblzhckisuran"}
        end
      }

      -- For showing the actual color of the hex value
      use "norcalli/nvim-colorizer.lua"

      -- Themes
      use "nanotech/jellybeans.vim"

      -- vim.cmd "let g:doom_one_terminal_colors = v:true"
      -- use "romgrk/doom-one.vim"
      use "tomasr/molokai"
      use "rafamadriz/neon"
      use "Mofiqul/vscode.nvim"
      use "marko-cerovac/material.nvim"
      use "ray-x/aurora"
      use "mhartington/oceanic-next"

      -- Neovim LSP
      use "neovim/nvim-lspconfig"

      -- show signatures of functions as you type
      use {
        "ray-x/lsp_signature.nvim"
      }

      -- better display of reference lists, etc.
      -- use {
      --   "folke/trouble.nvim",
      --   requires = "kyazdani42/nvim-web-devicons",
      -- }

      -- for using prettier / eslint
      use "mhartington/formatter.nvim"

      -- Neovim Completion
      use "onsails/lspkind.nvim"
      use {
        "hrsh7th/nvim-cmp",
        requires = {
          "hrsh7th/cmp-nvim-lsp",
          "hrsh7th/cmp-buffer",
          "hrsh7th/cmp-path",
          "saadparwaiz1/cmp_luasnip",
          "L3MON4D3/LuaSnip"
          -- "hrsh7th/vim-vsnip",
          -- "hrsh7th/vim-vsnip-integ",
          -- "hrsh7th/cmp-nvim-lua",
          -- "hrsh7th/cmp-vsnip",
        }
      }

      -- use {
      --   "zbirenbaum/copilot.lua",
      --   requires = {
      --     "nvim-lua/plenary.nvim"
      --   }
      -- }
      --
      -- use {
      --   "CopilotC-Nvim/CopilotChat.nvim",
      --   branch = "canary"
      -- }

      use {
        "frankroeder/parrot.nvim",
        dependencies = {"ibhagwan/fzf-lua", "nvim-lua/plenary.nvim", "rcarriga/nvim-notify"},
        -- optionally include "rcarriga/nvim-notify" for beautiful notifications
        config = function()
          require("parrot").setup {
            providers = {
              anthropic = {
                api_key = os.getenv "ANTHROPIC_API_KEY"
              }
            }
          }
        end
      }

      use "mfussenegger/nvim-jdtls"

      -- use {
      --   "ms-jpq/coq_nvim",
      --   branch = "coq"
      -- }

      -- use {
      --   "ms-jpq/coq.artifacts",
      --   branch = "artifacts"
      -- }

      -- use {
      --   "ms-jpq/coq.thirdparty",
      --   branch = "3p"
      -- }

      -- Treesitter config
      use {
        "nvim-treesitter/nvim-treesitter",
        run = ":TSUpdate"
      }
      use {
        "nvim-treesitter/nvim-treesitter-context"
      }
      -- use {
      --   "hashivim/vim-terraform"
      -- }

      -- Treesitter for movement / selection
      -- use {
      --   "~/src/nvim-treesitter-textobjects",
      --   as = "nvim-treesitter/nvim-treesitter-textobjects"
      -- }
      use "nvim-treesitter/nvim-treesitter-textobjects"
      --use "nvim-treesitter/nvim-treesitter-textobjects"

      use "nvim-treesitter/playground"

      -- use "folke/lua-dev.nvim"
    end
  }
)
