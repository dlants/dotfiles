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
      -- use "junegunn/fzf.vim"
      use {
        'nvim-telescope/telescope.nvim', tag = '0.1.0',
      -- or                            , branch = '0.1.x',
        requires = { {'nvim-lua/plenary.nvim'} }
      }
      -- use { 'ibhagwan/fzf-lua',
      --   -- optional for icon support
      --   requires = { 'kyazdani42/nvim-web-devicons' }
      -- }
      use "ThePrimeagen/harpoon"

      -- grep
      use "mhinz/vim-grepper"

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
          require("gitsigns").setup {
            signs = {
              add = {hl = "GitSignsAdd", text = "+", numhl = "GitSignsAddNr", linehl = "GitSignsAddLn"},
              change = {hl = "GitSignsChange", text = "|", numhl = "GitSignsChangeNr", linehl = "GitSignsChangeLn"},
              delete = {hl = "GitSignsDelete", text = "_", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn"},
              topdelete = {hl = "GitSignsDelete", text = "‾", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn"},
              changedelete = {
                hl = "GitSignsChange",
                text = "~",
                numhl = "GitSignsChangeNr",
                linehl = "GitSignsChangeLn"
              }
            }
          }
        end
      }
      use "tpope/vim-fugitive"
      use "tpope/vim-rhubarb"

      -- vim enhancements (motion, repeatability)
      use "tpope/vim-commentary"
      -- use "tpope/vim-unimpaired"
      use "tpope/vim-abolish"

      -- incompatible w/ compe
      -- use { 'tpope/vim-endwise' }
      use "tpope/vim-repeat"
      use "tpope/vim-surround"

      -- Neovim motions on speed!
      use {
        "/phaazon/hop.nvim",
        as = "hop",
        config = function()
          require("hop").setup {}
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
      use 'Mofiqul/vscode.nvim'
      use 'marko-cerovac/material.nvim'
      use 'ray-x/aurora'
      use 'mhartington/oceanic-next'

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
