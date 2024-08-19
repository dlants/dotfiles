return {
  -- {"wbthomason/packer.nvim", opt = true},
  -- Make it easier to navigate between tmux and vim panes
  {"christoomey/vim-tmux-navigator"},
  -- Trim whitespace on save
  {"ntpeters/vim-better-whitespace"},
  -- navigation / grep
  -- {"junegunn/fzf.vim", dependencies = {"junegunn/fzf", build = ":call fzf#install()"
  -- required by fzf-lua
  {"junegunn/fzf", build = "./install --bin"},
  -- {"nvim-telescope/telescope-fzf-native.nvim", build = "make"}
  -- {
  --   "nvim-telescope/telescope.nvim",
  --   tag = "0.1.0",
  --   -- or                            , branch = '0.1.x',
  --   dependencies = {{"nvim-lua/plenary.nvim"}}
  -- }
  {
    "ibhagwan/fzf-lua",
    -- optional for icon support
    dependencies = {"nvim-tree/nvim-web-devicons"},
    config = function()
      require "fzf-lua".setup({"default"})
    end
  },
  -- "ThePrimeagen/harpoon"

  -- grep
  {"mhinz/vim-grepper"},
  -- navigation
  -- {
  --   "nvim-tree/nvim-tree.lua",
  --   dependencies = {"nvim-tree/nvim-web-devicons"}
  -- }
  {
    "stevearc/oil.nvim",
    dependencies = {"nvim-tree/nvim-web-devicons"},
    config = function()
      -- from https://github.com/stevearc/oil.nvim?tab=readme-ov-file#quick-start
      require("oil").setup(
        {
          default_file_explorer = true,
          columns = {"icon"},
          keymaps = {
            ["<C-h>"] = false
          },
          view_options = {
            show_hidden = true
          }
        }
      )

      vim.keymap.set("n", "-", "<CMD>Oil<CR>", {desc = "Open parent directory"})
    end
  },
  -- For statusline
  {
    "hoob3rt/lualine.nvim",
    dependencies = {"kyazdani42/nvim-web-devicons", lazy = true},
    config = function()
      local function relative_path()
        return vim.api.nvim_exec("echo @%", true)
      end

      require "lualine".setup {
        options = {
          icons_enabled = true,
          theme = "jellybeans",
          component_separators = {"", ""},
          section_separators = {"", ""},
          disabled_filetypes = {}
        },
        sections = {
          lualine_a = {"mode"},
          lualine_b = {
            {
              "diagnostics",
              sources = {"nvim_lsp"}
            }
          },
          lualine_c = {relative_path},
          lualine_x = {"filetype"},
          lualine_y = {"branch"},
          lualine_z = {"diff"}
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = {relative_path},
          lualine_x = {},
          lualine_y = {},
          lualine_z = {}
        },
        tabline = {},
        extensions = {}
      }
    end
  },
  -- Git
  -- "mhinz/vim-signify"
  {
    "lewis6991/gitsigns.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim"
    },
    config = function()
      require("gitsigns").setup()
    end
  },
  {"tpope/vim-fugitive"},
  {
    "pwntester/octo.nvim",
    dependencies = {
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

      vim.keymap.set({"n", "v"}, "<leader>h", "<cmd>OpenInGHFileLines<cr>", {desc = "Open file in github"})
    end
  },
  -- quickly jump to file in github from nvim
  {"almo7aya/openingh.nvim"},
  {"tpope/vim-rhubarb"},
  -- vim enhancements (motion, repeatability)
  -- "tpope/vim-commentary"
  {
    "numToStr/Comment.nvim",
    config = function()
      require("Comment").setup()
    end
  },
  -- "tpope/vim-unimpaired"
  {"tpope/vim-abolish"},
  -- incompatible w/ compe
  -- { 'tpope/vim-endwise' }
  -- "tpope/vim-repeat"
  -- {"tpope/vim-surround"},
  -- Neovim motions on speed!
  -- {
  --   "smoka7/hop.nvim",
  --   tag = "*", -- optional but strongly recommended
  --   config = function()
  --     -- you can configure Hop the way you like here; see :h hop-config
  --     require "hop".setup {keys = "etovxqpdygfblzhckisuran"}
  --   end
  -- }
  {
    "ggandor/leap.nvim",
    config = function()
      require("leap").create_default_mappings()
    end
  },
  -- For showing the actual color of the hex value
  {"norcalli/nvim-colorizer.lua"},
  -- Themes
  {"nanotech/jellybeans.vim", lazy = true},
  -- vim.cmd "let g:doom_one_terminal_colors = v:true"
  -- "romgrk/doom-one.vim"
  {"tomasr/molokai", lazy = true},
  {"rafamadriz/neon", lazy = true},
  {"marko-cerovac/material.nvim", lazy = true},
  {"ray-x/aurora", lazy = true},
  {"mhartington/oceanic-next", lazy = true},
  -- Neovim LSP
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lsp = require "lspconfig"

      -- on_attach only maps when the language server attaches to the current buffer
      local on_attach = function(client, bufnr)
        local opts = {noremap = true, silent = true}
        local function buf_set_keymap(...)
          vim.api.nvim_buf_set_keymap(bufnr, ...)
        end

        buf_set_keymap("n", "<leader>t", [[<Cmd>lua vim.lsp.buf.hover()<CR>]], opts)
        buf_set_keymap("n", "<leader>d", [[<Cmd>lua vim.lsp.buf.definition()<CR>]], opts)
        buf_set_keymap("n", "<leader>D", [[<Cmd>lua vim.lsp.buf.declaration()<CR>]], opts)
        buf_set_keymap("n", "<leader>r", [[<Cmd>lua vim.lsp.buf.references()<CR>]], opts)
        buf_set_keymap("n", "<leader>R", [[<Cmd>lua vim.lsp.buf.rename()<CR>]], opts)
        -- buf_set_keymap('n', '<leader>`', [[<Cmd>lua vim.lsp.buf.formatting_sync()<CR>]], opts)

        buf_set_keymap("n", "<leader>i", [[<Cmd>lua vim.diagnostic.setloclist()<CR>]], opts)
        buf_set_keymap("n", "[e", [[<Cmd>lua vim.diagnostic.goto_prev()<CR>]], opts)
        buf_set_keymap("n", "]e", [[<Cmd>lua vim.diagnostic.goto_next()<CR>]], opts)
        buf_set_keymap("n", "<leader>f", [[<Cmd>lua vim.lsp.buf.format({async=true})<CR>]], opts)

        require "lsp_signature".on_attach {
          bind = true,
          hint_prefix = "",
          handler_opts = {
            border = "none"
          }
        }
      end

      local servers = {"dockerls", "bashls", "jsonls", "eslint", "yamlls"} -- "terraformls", "tflint",
      for _, server in ipairs(servers) do
        lsp[server].setup {
          on_attach = on_attach,
          flags = {
            debounce_text_changes = 150
          },
          capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
        }
      end

      lsp.tsserver.setup {
        init_options = {
          hostInfo = "neovim",
          maxTsServerMemory = 4096
        },
        on_attach = on_attach,
        flags = {
          debounce_text_changes = 150
        },
        capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
      }

      lsp.rust_analyzer.setup(
        {
          on_attach = on_attach,
          settings = {
            ["rust-analyzer"] = {
              assist = {
                importGranularity = "module",
                importPrefix = "self"
              },
              cargo = {
                loadOutDirsFromCheck = true
              },
              procMacro = {
                enable = true
              }
            }
          }
        }
      )
    end
  },
  -- show signatures of functions as you type
  {
    "ray-x/lsp_signature.nvim"
  },
  -- better display of reference lists, etc.
  -- {
  --   "folke/trouble.nvim",
  --   dependencies = "kyazdani42/nvim-web-devicons",
  -- }

  -- for using prettier / eslint
  {
    "mhartington/formatter.nvim",
    config = function()
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
          yaml = {
            function()
              return {
                exe = "npx prettier",
                args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
                stdin = true
              }
            end
          },
          html = {
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
            -- npm install -g lua-fmt
            function()
              return {
                exe = "luafmt",
                args = {"--indent-count", 2, "--stdin"},
                stdin = true
              }
            end
          },
          rust = {
            -- rustfmt
            function()
              return {
                exe = "rustfmt",
                args = {"--emit=stdout"},
                stdin = true
              }
            end
          },
          markdown = {
            function()
              return {
                exe = "prettier",
                args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
                stdin = true
              }
            end
          }
          -- terraform = {
          --   function()
          --     return {
          --       exe = "terraform",
          --       args = {"fmt", "-"},
          --       stdin = true
          --     }
          --   end
          -- }
        }
      }

      vim.api.nvim_set_keymap("n", "<leader>`", ":Format<CR>", {noremap = true})
    end
  },
  -- Neovim Completion
  {"onsails/lspkind.nvim"},
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip"
      -- "hrsh7th/vim-vsnip",
      -- "hrsh7th/vim-vsnip-integ",
      -- "hrsh7th/cmp-nvim-lua",
      -- "hrsh7th/cmp-vsnip",
    },
    config = function()
      local lspkind = require("lspkind")

      local has_words_before = function()
        if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
          return false
        end
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end
      local cmp = require "cmp"
      vim.o.completeopt = "menu,menuone,noselect"

      cmp.setup(
        {
          formatting = {
            format = lspkind.cmp_format(
              {
                with_text = true,
                menu = {
                  buffer = "[buf]",
                  -- luasnip = "[snip]",
                  nvim_lsp = "[lsp]",
                  nvim_lua = "[vim]",
                  path = "[path]"
                }
              }
            )
          },
          mapping = {
            ["<C-Space>"] = cmp.mapping(cmp.mapping.complete(), {"i", "c"}),
            ["<Tab>"] = cmp.mapping(
              function(fallback)
                -- if require("copilot.suggestion").is_visible() then
                --   require("copilot.suggestion").accept()
                -- elseif
                if cmp.visible() then
                  -- elseif luasnip.expandable() then
                  --   luasnip.expand()
                  cmp.select_next_item({behavior = cmp.SelectBehavior.Insert})
                elseif has_words_before() then
                  cmp.complete()
                else
                  fallback()
                end
              end,
              {
                "i",
                "s"
              }
            ),
            ["<S-Tab>"] = cmp.mapping(
              function()
                if cmp.visible() then
                  cmp.select_prev_item({behavior = cmp.SelectBehavior.Insert})
                end
              end,
              {
                "i",
                "s"
              }
            ),
            ["<CR>"] = cmp.mapping(cmp.mapping.confirm({select = true}), {"i", "c"}),
            -- ["<Esc>"] = cmp.mapping.abort(),
            ["<C-Down>"] = cmp.mapping(cmp.mapping.scroll_docs(3), {"i", "c"}),
            ["<C-Up>"] = cmp.mapping(cmp.mapping.scroll_docs(-3), {"i", "c"})
          },
          sources = cmp.config.sources(
            {
              {name = "nvim_lsp", priority = 3}
              -- {name = "luasnip", priority = 1}
            },
            {
              {name = "buffer"},
              {name = "path"}
            }
          )
        }
      )

      function set_keymap(mode, lhs, rhs, desc_or_opts, opts)
        if not opts then
          opts = type(desc_or_opts) == "table" and desc_or_opts or {desc = desc_or_opts}
        else
          opts.desc = desc_or_opts
        end
        vim.keymap.set(mode, lhs, rhs, opts)
      end
    end
  },
  -- {
  --   "zbirenbaum/copilot.lua",
  --   dependencies = {
  --     "nvim-lua/plenary.nvim"
  --   }
  -- }
  --
  -- {
  --   "CopilotC-Nvim/CopilotChat.nvim",
  --   branch = "canary"
  -- }

  {
    "frankroeder/parrot.nvim",
    dependencies = {"ibhagwan/fzf-lua", "nvim-lua/plenary.nvim", "rcarriga/nvim-notify"},
    -- optionally include "rcarriga/nvim-notify" for beautiful notifications
    config = function()
      require("parrot").setup {
        providers = {
          anthropic = {
            api_key = os.getenv "ANTHROPIC_API_KEY"
          }
        },
        chat_shortcut_respond = {modes = {"n"}, shortcut = "<CR>"},
        chat_shortcut_delete = {modes = {"n"}, shortcut = "<leader>d"},
        chat_shortcut_stop = {modes = {"n"}, shortcut = "<leader>s"},
        chat_shortcut_new = {modes = {"n"}, shortcut = "<leader>n"}
      }

      vim.keymap.set({"n", "v"}, "<leader>cc", "<cmd>PrtChatToggle vsplit<cr>", {desc = "Toggle Parrot Chat"})
      vim.keymap.set({"n", "v"}, "<leader>cn", "<cmd>PrtChatNew vsplit<cr>", {desc = "New Parrot Chat"})
      vim.keymap.set("v", "<leader>cp", ":<C-u>'<,'>PrtChatPaste vsplit<cr>", {desc = "Paste to Parrot Chat"})
      vim.keymap.set("v", "<leader>cr", ":<C-u>'<,'>PrtRewrite<cr>", {desc = "Rewrite with Parrot"})
      vim.keymap.set("v", "<leader>cA", ":<C-u>'<,'>PrtAppend<cr>", {desc = "Append with Parrot"})
      vim.keymap.set("v", "<leader>cI", ":<C-u>'<,'>PrtPrepend<cr>", {desc = "Prepend with Parrot"})
    end
  },
  {"mfussenegger/nvim-jdtls"},
  -- {
  --   "ms-jpq/coq_nvim",
  --   branch = "coq"
  -- }

  -- {
  --   "ms-jpq/coq.artifacts",
  --   branch = "artifacts"
  -- }

  -- {
  --   "ms-jpq/coq.thirdparty",
  --   branch = "3p"
  -- }

  -- Treesitter config
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require "nvim-treesitter.configs".setup {
        highlight = {
          enable = true
        },
        indent = {
          enable = true
        }
      }
    end
  },
  {
    "nvim-treesitter/nvim-treesitter-context"
  },
  -- {
  --   "hashivim/vim-terraform"
  -- }

  -- Treesitter for movement / selection
  -- {
  --   "~/src/nvim-treesitter-textobjects",
  --   as = "nvim-treesitter/nvim-treesitter-textobjects"
  -- }
  {"nvim-treesitter/nvim-treesitter-textobjects"},
  --"nvim-treesitter/nvim-treesitter-textobjects"

  {"nvim-treesitter/playground"}

  -- "folke/lua-dev.nvim"
}
