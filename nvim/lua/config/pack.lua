-- Native vim.pack plugin management (Neovim 0.12+)

-- Load magenta.nvim from local source (~/src/magenta.nvim)
local magenta_path = vim.fn.expand("~/src/magenta.nvim")
if vim.fn.isdirectory(magenta_path) == 1 then
  vim.opt.rtp:prepend(magenta_path)
  vim.opt.rtp:append(magenta_path .. "/after")
end

-- Remote plugins managed by vim.pack
vim.pack.add({
  "https://github.com/folke/snacks.nvim",
  "https://github.com/christoomey/vim-tmux-navigator",
  "https://github.com/ntpeters/vim-better-whitespace",
  { src = "https://github.com/junegunn/fzf", build = "./install --bin" },
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/ibhagwan/fzf-lua",
  "https://github.com/stevearc/oil.nvim",
  "https://github.com/hoob3rt/lualine.nvim",
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/lewis6991/gitsigns.nvim",
  "https://github.com/tpope/vim-fugitive",
  "https://github.com/NicolasGB/jj.nvim",
  "https://github.com/numtostr/comment.nvim",
  "https://github.com/kylechui/nvim-surround",
  { src = "https://github.com/catgoose/nvim-colorizer.lua", name = "catgoose-nvim-colorizer" },
  "https://github.com/j-hui/fidget.nvim",
  "https://github.com/p00f/alabaster.nvim",
  "https://github.com/neovim/nvim-lspconfig",
  "https://github.com/stevearc/conform.nvim",
  "https://github.com/mfussenegger/nvim-jdtls",
  "https://github.com/onsails/lspkind.nvim",
  "https://github.com/hrsh7th/nvim-cmp",
  "https://github.com/hrsh7th/cmp-nvim-lsp",
  "https://github.com/hrsh7th/cmp-buffer",
  "https://github.com/hrsh7th/cmp-nvim-lua",
  "https://github.com/hrsh7th/cmp-path",
  "https://github.com/hrsh7th/cmp-cmdline",
  "https://github.com/rcarriga/nvim-notify",
  "https://codeberg.org/andyg/leap.nvim",
  "https://github.com/neovim-treesitter/treesitter-parser-registry",
  { src = "https://github.com/neovim-treesitter/nvim-treesitter", version = "main" },
  "https://github.com/nvim-treesitter/nvim-treesitter-context",
  { src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects", version = "main" },
  "https://github.com/hashivim/vim-terraform",
})

-- Run fzf build on install/update
vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if name == "fzf" and kind == "update" then
      vim.fn.system({ "sh", "-c", "./install --bin" })
    end
    if name == "nvim-treesitter" and kind == "update" then
      if not ev.data.active then
        vim.cmd.packadd("nvim-treesitter")
      end
      vim.cmd("TSUpdate")
    end
  end
})
