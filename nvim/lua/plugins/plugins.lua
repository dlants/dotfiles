local function read_file_to_string(file_path)
  if vim.fn.filereadable(file_path) == 0 then
    print("File not found: " .. file_path)
    return nil
  end

  local lines = vim.fn.readfile(file_path)
  return table.concat(lines, "\n")
end

local llm_default_prompt =
  [[You are a coding assistant to a principal software engineer. Please be concise.
When you're not sure about something, say so but also take a guess. Prefer code samples to written explanations.]]

return {
  -- dev
  {
    dir = "~/src/magenta.nvim",
    build = ":UpdateRemotePlugins",
    lazy = false,
    config = function()
      vim.api.nvim_set_keymap("n", "<leader>m", ":Magenta toggle<CR>", {silent = true, noremap = true})
    end
  },
  {
    "sphamba/smear-cursor.nvim",
    opts = {}
  },
  {"christoomey/vim-tmux-navigator"},
  {"ntpeters/vim-better-whitespace"},
  -- { "junegunn/fzf",                  build = "./install --bin" },
  -- {
  --   "ibhagwan/fzf-lua",
  --   dependencies = { "nvim-tree/nvim-web-devicons" },
  --   opts = {
  --     winopts = {
  --       height = 0.5,
  --       width = 1.0,
  --       row = 0,
  --       border = "none"
  --     }
  --   },
  --   keys = {
  --     {
  --       "<leader>f",
  --       function()
  --         require("fzf-lua").git_files()
  --       end,
  --       desc = "FZF Git Files",
  --       silent = true
  --     },
  --     {
  --       "<leader>F",
  --       function()
  --         require("fzf-lua").files()
  --       end,
  --       desc = "FZF Git Files",
  --       silent = true
  --     }
  --     -- {
  --     --   "<leader>fH",
  --     --   function()
  --     --     require("fzf-lua").helptags_grep()
  --     --   end,
  --     --   desc = "FZF grep help",
  --     --   silent = true
  --     -- }
  --   }
  --   -- opts = {
  --   --   winopts = {
  --   --     preview = {default = "bat"}
  --   --   }
  --   -- }
  -- },
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.5",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      {"nvim-telescope/telescope-fzf-native.nvim", build = "make"}
    },
    keys = {
      {
        "<leader>f",
        function()
          require("telescope.builtin").git_files({show_untracked = true})
        end,
        desc = "Find Git Files"
      },
      {
        "<leader>F",
        function()
          require("telescope.builtin").find_files({hidden = true})
        end,
        desc = "Find Files"
      },
      {
        "<leader>/",
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Live Grep"
      },
      {
        "<leader>b",
        function()
          require("telescope.builtin").buffers()
        end,
        desc = "Find Buffers"
      },
      {
        "<leader>h",
        function()
          require("telescope.builtin").help_tags()
        end,
        desc = "Help Tags"
      }
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")

      telescope.setup(
        {
          defaults = {
            path_display = {"truncate"},
            -- sorting_strategy = "ascending",
            -- layout_config = {
            --   horizontal = {
            --     prompt_position = "top"
            --   }
            -- },
            mappings = {
              i = {
                ["<C-h>"] = "which_key",
                ["<C-u>"] = false,
                ["<C-d>"] = false,
                ["<C-j>"] = actions.move_selection_next,
                ["<C-k>"] = actions.move_selection_previous,
                ["<C-q>"] = actions.smart_send_to_qflist + actions.open_qflist,
                ["<esc>"] = actions.close,
                ["<CR>"] = actions.select_default + actions.center
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
      )
      telescope.load_extension("fzf")
    end
  },
  -- grep
  {
    "mhinz/vim-grepper",
    config = function()
      -- Configure grepper
      vim.g.grepper = {
        prompt_quote = 0,
        tools = {"rg"}
      }
    end,
    cmd = "Grepper", -- Load the plugin when the Grepper command is used
    keys = {
      {"<leader>g", ":Grepper<CR>", desc = "Open Grepper", noremap = true, silent = true}
    },
    lazy = true
  },
  {
    "stevearc/oil.nvim",
    dependencies = {"nvim-tree/nvim-web-devicons"},
    keys = {
      {"-", "<CMD>Oil<CR>", desc = "oil"}
    },
    lazy = true,
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
    end
  },
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
          theme = "github_dark_colorblind",
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
  -- nice notifications for lazy.nvim
  -- { "rcarriga/nvim-notify"},
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
  -- {
  --   "pwntester/octo.nvim",
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --     "nvim-telescope/telescope.nvim",
  --     "nvim-tree/nvim-web-devicons"
  --   },
  --   keys = {
  --     {"<leader>h", "<cmd>openinghfilelines<cr>", mode = {"n", "v"}, desc = "open file in github"}
  --   },
  --   config = function()
  --     require "octo".setup(
  --       {
  --         picker = "fzf-lua"
  --       }
  --     )
  --   end
  -- },
  {"almo7aya/openingh.nvim"},
  {"tpope/vim-rhubarb"},
  {
    "numtostr/comment.nvim",
    opts = {}
  },
  {"tpope/vim-surround"},
  {"tpope/vim-abolish"},
  -- for showing the actual color of the hex value
  {"norcalli/nvim-colorizer.lua"},
  -- Better quickfix window
  {
    "kevinhwang91/nvim-bqf",
    enabled = false,
    ft = "qf"
  },
  -- Show indentation guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      indent = {char = "│"},
      scope = {enabled = true}
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
  -- Treesitter textobjects for better code navigation
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = {"nvim-treesitter/nvim-treesitter"},
    config = function()
      require("nvim-treesitter.configs").setup(
        {
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
                ["]c"] = "@class.outer"
              },
              goto_previous_start = {
                ["[f"] = "@function.outer",
                ["[c"] = "@class.outer"
              }
            }
          }
        }
      )
    end
  },
  -- themes
  {
    "nanotech/jellybeans.vim",
    config = function()
      -- vim.cmd.colorscheme "jellybeans"
    end
  },
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    lazy = false, -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      require("github-theme").setup({})

      vim.cmd("colorscheme github_dark_colorblind")
    end
  },
  -- {
  --   "Shatur/neovim-ayu",
  --   config = function()
  --     require("ayu").setup({})
  --     vim.cmd.colorscheme "ayu"
  --   end
  -- },
  -- vim.cmd "let g:doom_one_terminal_/colors = v:true"
  -- "romgrk/doom-one.vim"
  {"tomasr/molokai", lazy = true},
  {"rafamadriz/neon", lazy = true},
  {"marko-cerovac/material.nvim", lazy = true},
  {"ray-x/aurora", lazy = true},
  {"mhartington/oceanic-next", lazy = true},
  -- neovim lsp
  {
    "neovim/nvim-lspconfig",
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
      local capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
      capabilities.textDocument.completion.completionItem.snippetSupport = true

      -- on_attach only maps when the language server attaches to the current buffer
      local on_attach = function(client, bufnr)
        local function buf_set_keymap(mode, lhs, rhs)
          vim.keymap.set(mode, lhs, rhs, {buffer = bufnr, noremap = true, silent = true})
        end

        -- LSP actions
        buf_set_keymap("n", "<leader>k", vim.lsp.buf.hover)
        buf_set_keymap("n", "gd", vim.lsp.buf.definition)
        buf_set_keymap("n", "gD", vim.lsp.buf.declaration)
        buf_set_keymap("n", "gi", vim.lsp.buf.implementation)
        buf_set_keymap("n", "gr", vim.lsp.buf.references)
        buf_set_keymap("n", "<leader>r", vim.lsp.buf.rename)
        buf_set_keymap("n", "<leader>x", vim.lsp.buf.code_action)
        buf_set_keymap("n", "<leader>D", vim.lsp.buf.type_definition)

        -- Diagnostics
        buf_set_keymap("n", "<leader>d", vim.diagnostic.setloclist)
        buf_set_keymap("n", "[d", vim.diagnostic.goto_prev)
        buf_set_keymap("n", "]d", vim.diagnostic.goto_next)
        buf_set_keymap("n", "<leader>e", vim.diagnostic.open_float)

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

        -- Formatting
        -- buf_set_keymap(
        --   "n",
        --   "<leader>`",
        --   function()
        --     vim.lsp.buf.format({ async = true })
        --   end
        -- )
        --
        -- Auto format on save if the LSP supports it
        -- if client.server_capabilities.documentFormattingProvider then
        --   vim.api.nvim_create_autocmd(
        --     "BufWritePre",
        --     {
        --       group = vim.api.nvim_create_augroup("Format" .. bufnr, { clear = true }),
        --       buffer = bufnr,
        --       callback = function()
        --         vim.lsp.buf.format()
        --       end
        --     }
        --   )
        -- end

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

      -- TypeScript specific configuration
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
  -- {
  --   "folke/lazydev.nvim",
  --   ft = "lua", -- only load on lua files
  --   opts = {
  --     library = {
  --       -- See the configuration section for more details
  --       -- Load luvit types when the `vim.uv` word is found
  --       { path = "${3rd}/luv/library", words = { "vim%.uv" } },
  --     },
  --   },
  -- },
  {
    "ray-x/lsp_signature.nvim"
  },
  {
    "mhartington/formatter.nvim",
    keys = {
      {"<leader>`", ":Format<CR>", desc = "Format", mode = "n"}
    },
    config = function()
      -- Define common formatters
      local prettier = function()
        return {
          exe = "npx prettier",
          args = {"--stdin-filepath", vim.api.nvim_buf_get_name(0)},
          stdin = true
        }
      end

      local rustfmt = function()
        return {
          exe = "rustfmt",
          args = {"--emit=stdout"},
          stdin = true
        }
      end

      local luafmt = function()
        return {
          exe = "luafmt",
          args = {"--indent-count", 2, "--stdin"},
          stdin = true
        }
      end

      -- Setup formatters for file types
      require("formatter").setup(
        {
          logging = false,
          filetype = {
            javascript = {prettier},
            typescript = {prettier},
            javascriptreact = {prettier},
            typescriptreact = {prettier},
            json = {prettier},
            yaml = {prettier},
            html = {prettier},
            css = {prettier},
            scss = {prettier},
            markdown = {prettier},
            rust = {rustfmt},
            lua = {luafmt}
            -- Add more file types and their formatters here
          }
        }
      )

      -- Format on save
      local augroup = vim.api.nvim_create_augroup("Format", {clear = true})
      vim.api.nvim_create_autocmd(
        "BufWritePost",
        {
          group = augroup,
          callback = function()
            vim.cmd("FormatWrite")
          end
        }
      )
    end
  },
  {
    "mfussenegger/nvim-jdtls",
    ft = {"java"},
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
        root_dir = require("jdtls.setup").find_root({".git", "mvnw", "gradlew"}),
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
          local opts = {noremap = true, silent = true}

          vim.keymap.set("n", "<leader>t", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "<leader>d", vim.lsp.buf.declaration, opts)
          vim.keymap.set("n", "<leader>r", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, opts)

          vim.keymap.set("n", "<leader>i", vim.diagnostic.setloclist, opts)
          vim.keymap.set("n", "[e", vim.diagnostic.goto_prev, opts)
          vim.keymap.set("n", "]e", vim.diagnostic.goto_next, opts)
          -- vim.keymap.set(
          --   "n",
          --   "<leader>`",
          --   function()
          --     vim.lsp.buf.format({ async = true })
          --   end,
          --   opts
          -- )

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
  {"onsails/lspkind.nvim"},
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip"
      -- "zbirenbaum/copilot.lua",
      -- "zbirenbaum/copilot-cmp",
    },
    config = function()
      local cmp = require "cmp"

      -- require("copilot").setup {
      --   suggestion = { enabled = false },
      --   panel = { enabled = false },
      -- }
      --
      -- require("copilot_cmp").setup()

      -- local has_words_before = function()
      --   if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
      --     return false
      --   end
      --   local line, col = unpack(vim.api.nvim_win_get_cursor(0))
      --   return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      -- end
      vim.opt.completeopt = {"menu", "menuone", "noselect"}

      local lspkind = require("lspkind")
      lspkind.init {
        symbol_map = {}
      }

      -- vim.api.nvim_set_hl(0, "CmpItemKindCopilot", { fg = "#6CC644" })

      local kind_formatter =
        lspkind.cmp_format {
        mode = "symbol_text",
        menu = {
          buffer = "[buf]",
          nvim_lsp = "[LSP]",
          nvim_lua = "[api]",
          path = "[path]",
          gh_issues = "[issues]"
        }
      }

      cmp.setup(
        {
          formatting = {
            fields = {"abbr", "kind", "menu"},
            expandable_indicator = true,
            format = kind_formatter
          },
          mapping = {
            ["<CR>"] = cmp.mapping(
              cmp.mapping.confirm({select = true, behaviour = cmp.SelectBehavior.Insert}),
              {"i", "c"}
            ),
            ["<Tab>"] = cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                else
                  fallback()
                end
              end,
              {"i", "s"}
            ),
            ["<S-Tab>"] = cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                else
                  fallback()
                end
              end,
              {"i", "s"}
            )
          },
          sources = {
            -- {
            --   name = "lazydev",
            --   group_index = 0,
            -- },
            -- { name = "copilot" },
            {name = "nvim_lsp"},
            {name = "path"},
            {name = "buffer"}
          }

          -- sorting = {
          --   priority_weight = 2,
          --   comparators = {
          --     -- require("copilot_cmp.comparators").prioritize,
          --
          --     -- Below is the default comparitor list and order for nvim-cmp
          --     cmp.config.compare.offset,
          --     -- cmp.config.compare.scopes, --this is commented in nvim-cmp too
          --     cmp.config.compare.exact,
          --     cmp.config.compare.score,
          --     cmp.config.compare.recently_used,
          --     cmp.config.compare.locality,
          --     cmp.config.compare.kind,
          --     cmp.config.compare.sort_text,
          --     cmp.config.compare.length,
          --     cmp.config.compare.order,
          --   },
          -- },
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
              next = "<C-j>",
              prev = "<C-k>",
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
        {desc = "Trigger copilot suggestion"}
      )
    end
  },
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "hrsh7th/nvim-cmp", -- Optional: For using slash commands and variables in the chat buffer
      "nvim-telescope/telescope.nvim", -- Optional: For using slash commands
      {"stevearc/dressing.nvim", opts = {}} -- Optional: Improves the default Neovim UI
    },
    config = function()
      require("codecompanion").setup(
        {
          opts = {
            system_prompt = function()
              return llm_default_prompt
            end
          },
          strategies = {
            chat = {
              adapter = "anthropic"
            },
            inline = {
              adapter = "anthropic"
            },
            agent = {
              adapter = "anthropic"
            }
          },
          display = {
            chat = {}
          },
          prompt_library = {
            ["dcgview"] = {
              strategy = "chat",
              description = "Teach the LLM about DCGView",
              opts = {
                slash_cmd = "dcgview"
              },
              prompts = {
                {
                  role = "user",
                  content = function()
                    return read_file_to_string("/Users/denislantsman/dcgview_prompt")
                  end
                }
              },
              contains_code = true
            }
          }
        }
      )

      vim.api.nvim_set_keymap("n", "<leader>ca", "<cmd>CodeCompanionActions<cr>", {noremap = true, silent = true})
      vim.api.nvim_set_keymap("v", "<leader>ca", "<cmd>CodeCompanionActions<cr>", {noremap = true, silent = true})
      vim.api.nvim_set_keymap("n", "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", {noremap = true, silent = true})
      vim.api.nvim_set_keymap("v", "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", {noremap = true, silent = true})
      vim.api.nvim_set_keymap("v", "<leader>cp", "<cmd>CodeCompanionChat Add<cr>", {noremap = true, silent = true})

      -- Expand 'cc' into 'CodeCompanion' in the command line
      vim.cmd([[cab cc CodeCompanion]])
    end
  },
  {
    "rcarriga/nvim-notify",
    config = function()
      vim.notify = require "notify"
    end
  },
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    opts = {
      provider = "claude",
      auto_suggestions_provider = "claude",
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-3-5-sonnet-20241022",
        temperature = 0,
        max_tokens = 4096
      },
      system_prompt = llm_default_prompt,
      behaviour = {
        auto_suggestions = false
      }
    }, -- set this if you want to always pull the latest change
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = "make",
    -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
      "zbirenbaum/copilot.lua",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = {"markdown", "Avante"}
        },
        ft = {"markdown", "Avante"}
      }
    },
    version = false
  },
  {
    "ggandor/leap.nvim",
    config = function()
      local leap = require("leap")

      -- custom function to leap in both directions
      local function leap_bidirectional()
        local current_window = vim.fn.win_getid()
        leap.leap {target_windows = {current_window}}
      end

      -- set up the keybinding
      vim.keymap.set({"n", "x", "o"}, "s", leap_bidirectional, {silent = true, desc = "leap forward or backward"})
    end
  },
  {"mfussenegger/nvim-jdtls"},
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup {
        "core",
        "stable"
      }

      require("nvim-treesitter.configs").setup(
        {
          ensure_installed = {"teal"},
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
