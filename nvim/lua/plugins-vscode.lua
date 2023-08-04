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
      use "tpope/vim-repeat"
      use "tpope/vim-surround"
      use {
        "phaazon/hop.nvim",
        branch = "v2", -- optional but strongly recommended
        config = function()
          -- you can configure Hop the way you like here; see :h hop-config
          require "hop".setup {keys = "etovxqpdygfblzhckisuran"}
        end
      }
    end
  }
)
