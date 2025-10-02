return {
  {
    "dlants/magenta.nvim",
    lazy = false,
    dev = true,
    build = "npm install --frozen-lockfile",
    config = function()
      require("magenta").setup({
        -- debug = true,
        profiles = {
          {
            name = "claude-4-sonnet(max)",
            provider = "anthropic",
            model = "claude-sonnet-4-20250514",
            authType = "max",
            thinking = {
              enabled = true,
              budgetTokens = 1024
            }
          }, {
          name = "claude-4-sonnet",
          provider = "anthropic",
          model = "claude-sonnet-4-20250514",
          apiKeyEnvVar = "ANTHROPIC_API_KEY",
          thinking = {
            enabled = true,
            budgetTokens = 1024
          }
        },
          {
            name = "claude-3-7",
            provider = "anthropic",
            model = "claude-3-7-sonnet-latest",
            apiKeyEnvVar = "ANTHROPIC_API_KEY"
          },
          {
            name = "gpt-5",
            provider = "openai",
            model = "gpt-5",
            -- apiKeyEnvVar= "AMPLIFY_API_KEY",
            -- baseUrl= "https://amplify-llm-gateway-devci.poc.learning.amplify.com"
          },
          {
            name = "codex-mini",
            provider = "openai",
            model = "codex-mini-latest",
            apiKeyEnvVar = "OPENAI_API_KEY"
          },
          {
            name = "o4-mini",
            provider = "openai",
            model = "o4-mini",
            apiKeyEnvVar = "OPENAI_API_KEY"
          },
          {
            name = "copilot-claude-3-7",
            provider = "copilot",
            model = "claude-3.7-sonnet",
          }
        },
        sidebarPosition = "left",
        editPrediction = {
          profile = {
            provider = "anthropic",
            model = "claude-sonnet-4-20250514",
            apiKeyEnvVar = "ANTHROPIC_API_KEY",
          }
        },
        mcpServers = {
          -- Hub = {
          --   url = "http://localhost:37373/mcp"
          -- },
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
  -- {
  --   "sphamba/smear-cursor.nvim",
  --   opts = {}
  -- },
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    config = function()
      require("snacks").setup({
        input = {},
        indent = {},
        rename = {},
        bigfile = {
          notify = true
        },
      })
    end
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
        performance_mode = true,
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
        },
        previewers = {
          builtin = {
            extensions = {
              ["png"] = false,
              ["jpg"] = false,
              ["jpeg"] = false,
              ["gif"] = false,
              ["webp"] = false,
            }
          }
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
          require("fzf-lua").files({
            fd_opts = "--color=never --type f --hidden --follow --no-ignore"
          })
        end,
        desc = "FZF All Files (including gitignored)",
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

      -- Integration with snacks.nvim rename plugin
      vim.api.nvim_create_autocmd("User", {
        pattern = "OilActionsPost",
        callback = function(event)
          if event.data.actions.type == "move" then
            require("snacks").rename.on_rename_file(event.data.actions.src_url, event.data.actions.dest_url)
          end
        end,
      })
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

      -- Only set gitsigns navigation when not in fugitive diff buffers
      vim.keymap.set('n', ']c', function()
        if vim.wo.diff then
          return ']c'
        end
        vim.schedule(function() require('gitsigns').nav_hunk('next') end)
        return '<Ignore>'
      end, { expr = true, desc = 'Next git hunk' })

      vim.keymap.set('n', '[c', function()
        if vim.wo.diff then
          return '[c'
        end
        vim.schedule(function() require('gitsigns').nav_hunk('prev') end)
        return '<Ignore>'
      end, { expr = true, desc = 'Previous git hunk' })
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
  {
    "norcalli/nvim-colorizer.lua",
    config = function()
      require('colorizer').setup({
        '*',                      -- Highlight all files, but customize some others.
        css = { rgb_fn = true, }, -- Enable parsing rgb(...) functions in css.
        html = { names = false, } -- Disable parsing "names" like Blue or Gray
      }, {
        RGB = true,               -- #RGB hex codes
        RRGGBB = true,            -- #RRGGBB hex codes
        RRGGBBAA = true,          -- #RRGGBBAA hex codes
        names = false,            -- "Name" codes like Blue
        rgb_fn = false,           -- CSS rgb() and rgba() functions
        hsl_fn = false,           -- CSS hsl() and hsla() functions
        css = false,              -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
        css_fn = false,           -- Enable all CSS *functions*: rgb_fn, hsl_fn
        mode = 'background',      -- Set the display mode.
      })
    end
  },
  -- {
  --   "kevinhwang91/nvim-bqf",
  --   enabled = false,
  --   ft = "qf"
  -- },
  -- {
  --   "lukas-reineke/indent-blankline.nvim",
  --   main = "ibl",
  --   opts = {
  --     indent = { char = "│" },
  --     scope = { enabled = true }
  --   }
  -- },
  -- Show LSP progress
  {
    "j-hui/fidget.nvim",
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
  -- {
  --   "nanotech/jellybeans.vim",
  --   config = function()
  --     -- vim.cmd.colorscheme "jellybeans"
  --   end
  -- },
  {
    "0xstepit/flow.nvim",
    lazy = false,
    config = function()
      require("flow").setup {
        theme = {
          contrast = "high"
        },
      }
      vim.cmd("colorscheme flow")
    end
  },
  -- {
  --   "rebelot/kanagawa.nvim",
  --   lazy = false,
  --   config = function()
  --     require("kanagawa").setup {}
  --     vim.cmd("colorscheme kanagawa-dragon")
  --   end
  -- },
  -- {
  --   "ellisonleao/gruvbox.nvim",
  --   config = function()
  --     require("gruvbox").setup {
  --       contrast = "hard"
  --     }
  --   end
  -- },
  -- {
  --   "sainnhe/gruvbox-material",
  --   config = function()
  --     vim.g.gruvbox_material_background = 'hard'
  --     vim.g.gruvbox_material_ui_contrast = 'high'
  --     vim.cmd("colorscheme gruvbox-material")
  --   end
  -- },
  -- {
  --   "projekt0n/github-nvim-theme",
  --   name = "github-theme",
  --   lazy = false,    -- make sure we load this during startup if it is your main colorscheme
  --   priority = 1000, -- make sure to load this before all the other start plugins
  --   config = function()
  --     --require("github-theme").setup({})
  --     --vim.cmd("colorscheme github_dark_colorblind")
  --   end
  -- },
  -- {
  --   "craftzdog/solarized-osaka.nvim",
  --   lazy = false,
  --   priority = 1000,
  --   opts = {},
  --   config = function()
  --     --vim.cmd("colorscheme solarized-osaka")
  --   end
  -- },
  -- { "tomasr/molokai",              lazy = true },
  -- { "rafamadriz/neon",             lazy = true },
  -- { "marko-cerovac/material.nvim", lazy = true },
  -- { "ray-x/aurora",                lazy = true },
  -- { "mhartington/oceanic-next",    lazy = true },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = {
      "hrsh7th/cmp-nvim-lsp"
    },
    config = function()
      -- Add proper diagnostic configuration
      vim.diagnostic.config(
        {
          virtual_text = false,  -- Disable regular virtual text to avoid redundancy
          virtual_lines = false, -- Disable virtual lines by default
          signs = true,
          underline = true,
          update_in_insert = false,
          severity_sort = true
        }
      )

      -- Clear hovers when switching buffers
      -- vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      --   callback = function()
      --     -- Close any floating windows (including LSP hovers)
      --     for _, winid in pairs(vim.api.nvim_tabpage_list_wins(0)) do
      --       if vim.api.nvim_win_get_config(winid).relative ~= "" then
      --         vim.api.nvim_win_close(winid, false)
      --       end
      --     end
      --   end,
      -- })

      -- Function to temporarily show virtual lines
      local function show_virtual_lines_until_next_move()
        vim.diagnostic.config({ virtual_lines = true })

        -- Hide when cursor moves, with delay to allow diagnostic jump to complete
        vim.defer_fn(function()
          vim.api.nvim_create_autocmd("CursorMoved", {
            once = true,
            callback = function()
              vim.diagnostic.config({ virtual_lines = false })
            end
          })
        end, 50)
      end

      -- Setup capabilities properly
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      capabilities.textDocument.completion.completionItem.snippetSupport = true

      -- on_attach only maps when the language server attaches to the current buffer
      local on_attach = function(_, bufnr)
        local function buf_set_keymap(mode, lhs, rhs)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, noremap = true, silent = true })
        end

        -- LSP actions
        buf_set_keymap("n", "<leader>k", vim.lsp.buf.hover)
        buf_set_keymap("n", "gd", vim.lsp.buf.definition)
        buf_set_keymap("n", "gD", vim.lsp.buf.type_definition)
        buf_set_keymap("n", "gi", vim.lsp.buf.implementation)
        buf_set_keymap("n", "gr", vim.lsp.buf.references)
        buf_set_keymap("n", "<leader>r", vim.lsp.buf.rename)
        --buf_set_keymap("n", "<leader>x", vim.lsp.buf.code_action)
        buf_set_keymap("n", "<leader>x", [[:FzfLua lsp_code_actions<CR>]])
        buf_set_keymap("n", "<leader>D", vim.lsp.buf.type_definition)

        -- Signature help
        buf_set_keymap("i", "<C-s>", vim.lsp.buf.signature_help)

        -- Diagnostics
        buf_set_keymap("n", "<leader>d", vim.diagnostic.setqflist)
        buf_set_keymap("n", "[d", function()
          vim.diagnostic.jump({ count = -1, float = false })
          show_virtual_lines_until_next_move()
        end)
        buf_set_keymap("n", "]d", function()
          vim.diagnostic.jump({ count = 1, float = false })
          show_virtual_lines_until_next_move()
        end)
        buf_set_keymap("n", "<leader>e", function()
          show_virtual_lines_until_next_move()
        end)

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
      end

      -- Default configuration for all servers
      local default_config = {
        on_attach = on_attach,
        capabilities = capabilities,
        flags = {
          debounce_text_changes = 500
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
        vim.lsp.config(server, default_config)
      end

      vim.lsp.config("ts_ls",
        vim.tbl_extend(
          "force",
          default_config,
          {
            init_options = {
              hostInfo = "neovim",
              preferences = {
                importModuleSpecifierPreference = "relative"
              }
            },
            capabilities = vim.tbl_extend(
              "force",
              capabilities,
              {
                textDocument = {
                  signatureHelp = nil
                }
              }
            ),
            flags = {
              debounce_text_changes = 1000
            }
          }
        ))


      -- Rust specific configuration
      vim.lsp.config("rust_analyzer",
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

      vim.lsp.config("lua_ls", {
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
      })

      vim.lsp.config("zls", {
        on_attach = on_attach,
        capabilities = capabilities,
        -- There are two ways to set config options:
        --   - edit your `zls.json` that applies to any editor that uses ZLS
        --   - set in-editor config options with the `settings` field below.
        --
        -- Further information on how to configure ZLS:
        -- https://zigtools.org/zls/configure/
        settings = {
          zls = {
            -- Whether to enable build-on-save diagnostics
            --
            -- Further information about build-on save:
            -- https://zigtools.org/zls/guides/build-on-save/
            -- enable_build_on_save = true,

            -- Neovim already provides basic syntax highlighting
            semantic_tokens = "partial",
          }
        }
      })
    end
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
        end
      }
      -- this starts a new client & server,
      -- or attaches to an existing client & server depending on the `root_dir`.
      require("jdtls").start_or_attach(config)
    end
  },
  { "onsails/lspkind.nvim" },
  -- magazine.nvim, from https://github.com/iguanacucumber/magazine.nvim
  -- { "iguanacucumber/mag-nvim-lsp", name = "cmp-nvim-lsp", opts = {} },
  -- { "iguanacucumber/mag-nvim-lua", name = "cmp-nvim-lua" },
  -- { "iguanacucumber/mag-buffer",   name = "cmp-buffer" },
  -- { "iguanacucumber/mag-cmdline",  name = "cmp-cmdline" },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-nvim-lua",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      -- "saadparwaiz1/cmp_luasnip",
      -- "L3MON4D3/LuaSnip"
      -- "zbirenbaum/copilot.lua",
      -- "zbirenbaum/copilot-cmp",
    },
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

      -- Setup filetype-specific sources
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          cmp.setup.buffer {
            sources = cmp.config.sources({
              { name = "nvim_lsp" },
              { name = "nvim_lua" },
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
            })
          }
        end
      })
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
          ensure_installed = {
            "lua", "typescript", "javascript", "tsx", "json", "yaml",
            "html", "css", "rust", "bash", "markdown", "teal"
          },
          highlight = {
            enable = true,
            additional_vim_regex_highlighting = false,
            disable = function(lang, buf)
              local max_filesize = 100 * 1024 -- 100 KB
              local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
              if ok and stats and stats.size > max_filesize then
                return true
              end
            end,
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
              ["]a"] = "@parameter.inner"
            },
            goto_next_end = {
              ["]F"] = "@function.outer"
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[a"] = "@parameter.inner"
            },
            goto_previous_end = {
              ["[F"] = "@function.outer"
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
