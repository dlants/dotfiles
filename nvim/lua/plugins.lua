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

      -- fzf
      use "junegunn/fzf.vim"

      -- grep
      use "mhinz/vim-grepper"

      -- For statusline
      use {
        "hoob3rt/lualine.nvim",
        requires = {"kyazdani42/nvim-web-devicons", opt = true}
      }

      -- Git
      use "mhinz/vim-signify"
      use "tpope/vim-fugitive"
      use "tpope/vim-rhubarb"

      -- vim enhancements (motion, repeatability)
      use "tpope/vim-commentary"
      use "tpope/vim-unimpaired"
      use "tpope/vim-abolish"

      -- incompatible w/ compe
      -- use { 'tpope/vim-endwise' }
      use "tpope/vim-repeat"
      use "tpope/vim-surround"

      -- Neovim motions on speed!
      use {
        "phaazon/hop.nvim",
        as = "hop",
        config = function()
          require("hop").setup {}
        end
      }

      -- For showing the actual color of the hex value
      use "norcalli/nvim-colorizer.lua"

      -- Themes
      use "nanotech/jellybeans.vim"

      -- Neovim LSP
      use "neovim/nvim-lspconfig"

      -- for using prettier / eslint
      use "mhartington/formatter.nvim"

      -- Neovim Completion
      use "hrsh7th/nvim-compe"

      use {
        "nvim-treesitter/nvim-treesitter",
        run = ":TSUpdate"
      }
    end
  }
)
