return {
  {
    "dlants/magenta.nvim",
    lazy = false,
    dev = true,
    build = "npm install --frozen-lockfile",
    config = function()
      require("magenta").setup({
        profiles = {
          {
            name = "claude-4-sonnet",
            provider = "anthropic",
            model = "claude-sonnet-4-20250514",
            apiKeyEnvVar = "ANTHROPIC_API_KEY"
          },
          {
            name = "claude-3-7",
            provider = "anthropic",
            model = "claude-3-7-sonnet-latest",
            apiKeyEnvVar = "ANTHROPIC_API_KEY"
          },
          {
            name = "claude-4-opus",
            provider = "anthropic",
            model = "claude-opus-4-20250514",
            apiKeyEnvVar = "ANTHROPIC_API_KEY"
          },
          {
            name = "gpt-4.1",
            provider = "openai",
            model = "gpt-4.1",
            -- apiKeyEnvVar= "AMPLIFY_API_KEY",
            -- baseUrl= "https://amplify-llm-gateway-devci.poc.learning.amplify.com"
          },
          {
            name = "copilot-claude-3-7",
            provider = "copilot",
            model = "claude-3.7-sonnet",
          }
        },
        sidebarPosition = "left",

        mcpServers = {
          playwright = {
            command = "npx",
            args = {
              "@playwright/mcp@latest"
            }
          }
        }

      })
    end
  },
  {
    "sphamba/smear-cursor.nvim",
    opts = {}
  },
  {
    "karb94/neoscroll.nvim",
    config = function()
      require("neoscroll").setup({
        hide_cursor = true,
        stop_eof = true,
        respect_scrolloff = false,
        cursor_scrolls_alone = true,
        easing_function = nil,
        performance_mode = false,
      })

      -- Custom key mappings with faster scroll speed
      local neoscroll = require('neoscroll')
      local keymap = {
        -- Faster scrolling - reduce the time values to speed up
        ["<C-u>"] = function() neoscroll.ctrl_u({ duration = 50 }) end,
        ["<C-d>"] = function() neoscroll.ctrl_d({ duration = 50 }) end,
        ["<C-b>"] = function() neoscroll.ctrl_b({ duration = 75 }) end,
        ["<C-f>"] = function() neoscroll.ctrl_f({ duration = 75 }) end,
        ["<C-y>"] = function() neoscroll.scroll(-0.1, { move_cursor = false, duration = 25 }) end,
        ["<C-e>"] = function() neoscroll.scroll(0.1, { move_cursor = false, duration = 25 }) end,
        ["zt"]    = function() neoscroll.zt({ half_win_duration = 50 }) end,
        ["zz"]    = function() neoscroll.zz({ half_win_duration = 50 }) end,
        ["zb"]    = function() neoscroll.zb({ half_win_duration = 50 }) end,
      }

      local modes = { 'n', 'v', 'x' }
      for key, func in pairs(keymap) do
        vim.keymap.set(modes, key, func)
      end
    end
  },
  { "christoomey/vim-tmux-navigator" },
  { "ntpeters/vim-better-whitespace" },
  { "junegunn/fzf",                  build = "./install --bin" },
  {
    "ibhagwan/fzf-lua",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("fzf-lua").setup({
        winopts = {
          height = 0.5,
          width = 1.0,
          row = 0,
          border = "none"
        }
      })
      require("fzf-lua").register_ui_select()
    end,
    code_actions = {
      previewer = "codeaction_native",
      preview_pager = "delta --side-by-side --width=$FZF_PREVIEW_COLUMNS"
    },
    keys = {
      {
        "<leader>F",
        function()
          require("fzf-lua").git_files()
        end,
        desc = "FZF Git Files",
        silent = true
      },
      {
        "<leader>f",
        function()
          require("fzf-lua").files()
        end,
        desc = "FZF Files",
        silent = true
      },
      {
        "<leader>h",
        function()
          require("fzf-lua").helptags()
        end,
        desc = "FZF grep help",
        silent = true
      },
      {
        "<leader>/",
        function()
          require("fzf-lua").live_grep()
        end,
        desc = "FZF live grep",
        silent = true
      }
    }
  },
  {
    "mhinz/vim-grepper",
    config = function()
      -- Configure grepper
      vim.g.grepper = {
        prompt_quote = 0,
        tools = { "rg" }
      }
    end,
    cmd = "Grepper", -- Load the plugin when the Grepper command is used
    keys = {
      { "<leader>g", ":Grepper<CR>", desc = "Open Grepper", noremap = true, silent = true }
    },
    lazy = true
  },
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "-", "<CMD>Oil<CR>", desc = "oil" }
    },
    lazy = false,
    config = function()
      -- from https://github.com/stevearc/oil.nvim?tab=readme-ov-file#quick-start
      require("oil").setup(
        {
          default_file_explorer = true,
          columns = { "icon" },
          keymaps = {
            ["<C-h>"] = false
          },
          view_options = {
            show_hidden = true
          }
        }
      )
    end
  },
  {
    "hoob3rt/lualine.nvim",
    dependencies = { "kyazdani42/nvim-web-devicons", lazy = true },
    config = function()
      local function relative_path()
        return vim.fn.expand("%")
      end

      require "lualine".setup {
        options = {
          icons_enabled = true,
          theme = "gruvbox",
          component_separators = { "", "" },
          section_separators = { "", "" },
          disabled_filetypes = {}
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = {
            {
              "diagnostics",
              sources = { "nvim_lsp" }
            }
          },
          lualine_c = { relative_path },
          lualine_x = { "filetype" },
          lualine_y = { "branch" },
          lualine_z = { "location" }
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { relative_path },
          lualine_x = {},
          lualine_y = {},
          lualine_z = {}
        },
        tabline = {},
        extensions = {}
      }
    end
  },
  {
    "lewis6991/gitsigns.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim"
    },
    config = function()
      require("gitsigns").setup()
    end
  },
  { "tpope/vim-fugitive" },
  { "almo7aya/openingh.nvim" },
  { "tpope/vim-rhubarb" },
  {
    "numtostr/comment.nvim",
    opts = {}
  },
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup({})
    end,
  },
  { "norcalli/nvim-colorizer.lua" },
  -- {
  --   "kevinhwang91/nvim-bqf",
  --   enabled = false,
  --   ft = "qf"
  -- },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      indent = { char = "│" },
      scope = { enabled = true }
    }
  },
  -- Show LSP progress
  {
    "j-hui/fidget.nvim",
    tag = "legacy",
    event = "LspAttach",
    opts = {
      text = {
        spinner = "dots"
      },
      window = {
        blend = 0
      }
    }
  },
  -- themes
  {
    "nanotech/jellybeans.vim",
    config = function()
      -- vim.cmd.colorscheme "jellybeans"
    end
  },
  {
    "0xstepit/flow.nvim",
    lazy = false,
    config = function()
      require("flow").setup {}
      vim.cmd("colorscheme flow")
    end
  },
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    lazy = false,    -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      --require("github-theme").setup({})
      --vim.cmd("colorscheme github_dark_colorblind")
    end
  },
  {
    "craftzdog/solarized-osaka.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
    config = function()
      --vim.cmd("colorscheme solarized-osaka")
    end
  },
  { "tomasr/molokai",              lazy = true },
  { "rafamadriz/neon",             lazy = true },
  { "marko-cerovac/material.nvim", lazy = true },
  { "ray-x/aurora",                lazy = true },
  { "mhartington/oceanic-next",    lazy = true },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = {
      "hrsh7th/cmp-nvim-lsp"
    },
    config = function()
      local lspkind = require "lspconfig"

      -- Add proper diagnostic configuration
      vim.diagnostic.config(
        {
          virtual_text = true,
          signs = true,
          underline = true,
          update_in_insert = false,
          severity_sort = true
        }
      )

      -- Setup capabilities properly
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      capabilities.textDocument.completion.completionItem.snippetSupport = true
      -- local capabilities = require("blink.cmp").get_lsp_capabilities()

      -- on_attach only maps when the language server attaches to the current buffer
      local on_attach = function(_, bufnr)
        local function buf_set_keymap(mode, lhs, rhs)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, noremap = true, silent = true })
        end

        -- LSP actions
        buf_set_keymap("n", "<leader>k", vim.lsp.buf.hover)
        buf_set_keymap("n", "gd", vim.lsp.buf.definition)
        buf_set_keymap("n", "gD", vim.lsp.buf.declaration)
        buf_set_keymap("n", "gi", vim.lsp.buf.implementation)
        buf_set_keymap("n", "gr", vim.lsp.buf.references)
        buf_set_keymap("n", "<leader>r", vim.lsp.buf.rename)
        --buf_set_keymap("n", "<leader>x", vim.lsp.buf.code_action)
        buf_set_keymap("n", "<leader>x", [[:FzfLua lsp_code_actions<CR>]])
        buf_set_keymap("n", "<leader>D", vim.lsp.buf.type_definition)

        -- Diagnostics
        buf_set_keymap("n", "<leader>d", vim.diagnostic.setqflist)
        buf_set_keymap("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end)
        buf_set_keymap("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end)
        buf_set_keymap("n", "<leader>e", function() vim.diagnostic.open_float() end)

        -- Workspace
        buf_set_keymap("n", "<leader>wa", vim.lsp.buf.add_workspace_folder)
        buf_set_keymap("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder)
        buf_set_keymap(
          "n",
          "<leader>wl",
          function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end
        )

        require "lsp_signature".on_attach {
          bind = true,
          hint_prefix = "",
          handler_opts = {
            border = "none"
          }
        }
      end

      -- Default configuration for all servers
      local default_config = {
        on_attach = on_attach,
        capabilities = capabilities,
        flags = {
          debounce_text_changes = 150
        }
      }

      local servers = {
        "bashls",
        "dockerls",
        "eslint",
        "jsonls",
        "terraformls",
        "tflint",
        "yamlls",
        "teal_ls"
      }

      for _, server in ipairs(servers) do
        lspkind[server].setup(default_config)
      end

      lspkind.ts_ls.setup(
        vim.tbl_extend(
          "force",
          default_config,
          {
            init_options = {
              hostInfo = "neovim",
              preferences = {
                importModuleSpecifierPreference = "relative"
              }
            }
          }
        )
      )

      -- Rust specific configuration
      lspkind.rust_analyzer.setup(
        vim.tbl_extend(
          "force",
          default_config,
          {
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
                },
                checkOnSave = {
                  command = "clippy"
                }
              }
            }
          }
        )
      )

      lspkind.lua_ls.setup {
        on_attach = on_attach,
        capabilities = capabilities,
        on_init = function(client)
          if client.workspace_folders then
            local path = client.workspace_folders[1].name
            if vim.fn.filereadable(path .. "/.luarc.json") or vim.fn.filereadable(path .. "/.luarc.jsonc") then
              return
            end
          end

          client.config.settings.Lua =
              vim.tbl_deep_extend(
                "force",
                client.config.settings.Lua,
                {
                  runtime = {
                    -- Tell the language server which version of Lua you're using
                    -- (most likely LuaJIT in the case of Neovim)
                    version = "LuaJIT"
                  },
                  -- Make the server aware of Neovim runtime files
                  workspace = {
                    checkThirdParty = false,
                    library = {
                      vim.env.VIMRUNTIME
                      -- Depending on the usage, you might want to add additional paths here.
                      -- "${3rd}/luv/library"
                      -- "${3rd}/busted/library",
                    }
                    -- or pull in all of 'runtimepath'. NOTE: this is a lot slower and will cause issues when working on your own configuration (see https://github.com/neovim/nvim-lspconfig/issues/3189)
                    -- library = vim.api.nvim_get_runtime_file("", true)
                  }
                }
              )
        end,
        settings = {
          Lua = {}
        }
      }
    end
  },
  {
    "ray-x/lsp_signature.nvim"
  },
  {
    "stevearc/conform.nvim",
    lazy = false,
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          javascript = { "prettier" },
          typescript = { "prettier" },
          javascriptreact = { "prettier" },
          typescriptreact = { "prettier" },
          json = { "prettier" },
          yaml = { "prettier" },
          html = { "prettier" },
          css = { "prettier" },
          scss = { "prettier" },
          markdown = { "prettier" },
          rust = { "rustfmt" },
        },
        format_on_save = {
          timeout_ms = 500,
          lsp_fallback = true,
        },
      })

      -- Set up the <leader>` keymap for manual formatting
      vim.keymap.set({ "n", "v" }, "<leader>`", function()
        require("conform").format({
          lsp_fallback = true,
          async = false,
          timeout_ms = 500,
        })
      end, { desc = "Format buffer" })
    end
  },
  {
    "mfussenegger/nvim-jdtls",
    ft = { "java" },
    config = function()
      local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
      local workspace_dir = "/users/denislantsman/src/" .. project_name
      local config = {
        -- the command that starts the language server
        -- see: https://github.com/eclipse/eclipse.jdt.ls#running-from-the-command-line
        cmd = {
          "/opt/homebrew/opt/openjdk/bin/java",
          "-declipse.application=org.eclipse.jdt.ls.core.id1",
          "-dosgi.bundles.defaultstartlevel=4",
          "-declipse.product=org.eclipse.jdt.ls.core.product",
          "-dlog.protocol=true",
          "-dlog.level=all",
          "-xmx1g",
          "--add-modules=all-system",
          "--add-opens",
          "java.base/java.util=all-unnamed",
          "--add-opens",
          "java.base/java.lang=all-unnamed",
          -- 💀
          "-jar",
          "/opt/homebrew/cellar/jdtls/1.38.0/libexec/plugins/org.eclipse.equinox.launcher_1.6.900.v20240613-2009.jar",
          -- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^                                       ^^^^^^^^^^^^^^
          -- must point to the                                                     change this to
          -- eclipse.jdt.ls installation                                           the actual version

          -- 💀
          "-configuration",
          "/opt/homebrew/cellar/jdtls/1.38.0/libexec/config_mac",
          -- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^        ^^^^^^
          -- must point to the                      change to one of `linux`, `win` or `mac`
          -- eclipse.jdt.ls installation            depending on your system.

          -- 💀
          -- see `data directory configuration` section in the readme
          "-data",
          workspace_dir
        },
        -- 💀
        -- this is the default if not provided, you can remove it. or adjust as needed.
        -- one dedicated lsp server & client will be started per unique root_dir
        root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew" }),
        -- here you can configure eclipse.jdt.ls specific settings
        -- see https://github.com/eclipse/eclipse.jdt.ls/wiki/running-the-java-ls-server-from-the-command-line#initialize-request
        -- for a list of options
        settings = {
          java = {}
        },
        -- language server `initializationoptions`
        -- you need to extend the `bundles` with paths to jar files
        -- if you want to use additional eclipse.jdt.ls plugins.
        --
        -- see https://github.com/mfussenegger/nvim-jdtls#java-debug-installation
        --
        -- if you don't plan on using the debugger or other eclipse.jdt.ls plugins you can remove this
        init_options = {
          bundles = {}
        },
        on_attach = function()
          local opts = { noremap = true, silent = true }

          vim.keymap.set("n", "<leader>t", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, opts)

          vim.keymap.set("n", "<leader>i", function() vim.diagnostic.setloclist() end, opts)
          vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, opts)
          vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, opts)
          vim.keymap.set(
            "n",
            "<leader>`",
            function()
              vim.lsp.buf.format({ async = true })
            end,
            opts
          )

          require "lsp_signature".on_attach {
            bind = true,
            hint_prefix = "",
            handler_opts = {
              border = "none"
            }
          }
        end
      }
      -- this starts a new client & server,
      -- or attaches to an existing client & server depending on the `root_dir`.
      require("jdtls").start_or_attach(config)
    end
  },
  { "onsails/lspkind.nvim" },
  -- magazine.nvim, from https://github.com/iguanacucumber/magazine.nvim
  { "iguanacucumber/mag-nvim-lsp", name = "cmp-nvim-lsp", opts = {} },
  { "iguanacucumber/mag-nvim-lua", name = "cmp-nvim-lua" },
  { "iguanacucumber/mag-buffer",   name = "cmp-buffer" },
  { "iguanacucumber/mag-cmdline",  name = "cmp-cmdline" },
  {
    "iguanacucumber/magazine.nvim",
    name = "nvim-cmp",
    -- "hrsh7th/nvim-cmp",
    -- dependencies = {
    --   "hrsh7th/cmp-nvim-lsp",
    --   "hrsh7th/cmp-buffer",
    --   "hrsh7th/cmp-path",
    --   "saadparwaiz1/cmp_luasnip",
    --   "L3MON4D3/LuaSnip"
    --   -- "zbirenbaum/copilot.lua",
    --   -- "zbirenbaum/copilot-cmp",
    -- },
    config = function()
      local cmp = require "cmp"

      vim.opt.completeopt = { "menu", "menuone", "noselect" }

      local lspkind = require("lspkind")
      lspkind.init {
        symbol_map = {
          Supermaven = "",
        }
      }

      local kind_formatter =
          lspkind.cmp_format {
            mode = "symbol_text",
            menu = {
              buffer = "[buf]",
              nvim_lsp = "[LSP]",
              nvim_lua = "[api]",
              path = "[path]",
              gh_issues = "[issues]",
              supermaven = "[AI]"
            }
          }

      cmp.setup(
        {
          formatting = {
            fields = { "abbr", "kind", "menu" },
            expandable_indicator = true,
            format = kind_formatter
          },
          mapping = {
            ["<CR>"] = cmp.mapping(
              cmp.mapping.confirm({ select = true, behavior = cmp.SelectBehavior.Insert }),
              { "i", "c" }
            ),
            ["<Tab>"] = cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                else
                  fallback()
                end
              end,
              { "i", "s" }
            ),
            ["<S-Tab>"] = cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                else
                  fallback()
                end
              end,
              { "i", "s" }
            ),
            ["<C-j>"] = cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                else
                  fallback()
                end
              end,
              { "i", "s" }
            ),
            ["<C-k>"] = cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                else
                  fallback()
                end
              end,
              { "i", "s" }
            )
          },
          sources = {
            { name = "nvim_lsp" },
            { name = "path" },
            {
              name = "buffer",
              option = {
                get_bufnrs = function()
                  local bufs = {}
                  for _, win in ipairs(vim.api.nvim_list_wins()) do
                    bufs[vim.api.nvim_win_get_buf(win)] = true
                  end
                  return vim.tbl_keys(bufs)
                end
              }
            }
          }
        }
      )
    end
  },
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup(
        {
          panel = {
            enabled = false
          },
          suggestion = {
            enabled = true,
            auto_trigger = false,
            hide_during_completion = false,
            debounce = 75,
            keymap = {
              accept_word = false,
              accept_line = false,
              -- next = "<C-j>",
              -- prev = "<C-k>",
              dismiss = "<Esc>"
            }
          }
        }
      )

      vim.keymap.set(
        "i",
        "<C-l>",
        function()
          local copilot = require("copilot.suggestion")
          if copilot.is_visible() then
            copilot.accept()
          else
            copilot.next()
          end
        end,
        { desc = "Trigger copilot suggestion" }
      )
    end
  },
  {
    "rcarriga/nvim-notify",
    config = function()
      vim.notify = require "notify"
    end
  },
  {
    "ggandor/leap.nvim",
    config = function()
      local leap = require("leap")

      -- custom function to leap in both directions
      local function leap_bidirectional()
        local current_window = vim.fn.win_getid()
        leap.leap { target_windows = { current_window } }
      end

      -- set up the keybinding
      vim.keymap.set({ "n", "x", "o" }, "s", leap_bidirectional, { silent = true, desc = "leap forward or backward" })
    end
  },
  { "mfussenegger/nvim-jdtls" },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup(
        {
          ensure_installed = { "teal" },
          highlight = {
            enable = true,
            additional_vim_regex_highlighting = false
          }
        }
      )
    end
  },
  {
    "nvim-treesitter/nvim-treesitter-context",
    config = function()
      require("treesitter-context").setup {
        enable = true
      }
    end
  },
  {
    "hashivim/vim-terraform"
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    config = function()
      require("nvim-treesitter.configs").setup {
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner"
            }
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]a"] = "@parameter.inner"
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer"
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[a"] = "@parameter.inner"
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer"
            }
          },
          swap = {}
        },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<cr>",
            node_incremental = "<cr>",
            scope_incremental = "<s-cr>",
            node_decremental = "<bs>"
          }
        }
      }
    end
  }
}
