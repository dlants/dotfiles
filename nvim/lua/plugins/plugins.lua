function read_file_to_string(file_path)
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
  {"christoomey/vim-tmux-navigator"},
  {"ntpeters/vim-better-whitespace"},
  {"junegunn/fzf", build = "./install --bin"},
  {
    "ibhagwan/fzf-lua",
    dependencies = {"nvim-tree/nvim-web-devicons"},
    keys = {
      {
        "<leader>p",
        function()
          require("fzf-lua").git_files()
        end,
        desc = "FZF Git Files",
        silent = true
      },
      {
        "<leader>o",
        function()
          require("fzf-lua").files()
        end,
        desc = "FZF Git Files",
        silent = true
      },
      {
        "<leader>fH",
        function()
          require("fzf-lua").helptags_grep()
        end,
        desc = "FZF grep help",
        silent = true
      }
    }
    -- opts = {
    --   winopts = {
    --     preview = {default = "bat"}
    --   }
    -- }
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
          -- theme = "jellybeans",
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
  -- themes
  {"nanotech/jellybeans.vim", lazy = true},
  -- vim.cmd "let g:doom_one_terminal_colors = v:true"
  -- "romgrk/doom-one.vim"
  {"tomasr/molokai", lazy = true},
  {"rafamadriz/neon", lazy = true},
  {"marko-cerovac/material.nvim", lazy = true},
  {"ray-x/aurora", lazy = true},
  {"mhartington/oceanic-next", lazy = true},
  -- neovim lsp
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

      local servers = {
        "bashls",
        "dockerls",
        "eslint",
        "jsonls",
        "terraformls",
        "tflint",
        "yamlls"
      }
      for _, server in ipairs(servers) do
        lsp[server].setup {
          on_attach = on_attach,
          flags = {
            debounce_text_changes = 150
          },
          capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
        }
      end

      lsp.ts_ls.setup {
        init_options = {
          hostInfo = "neovim"
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
  {
    "mhartington/formatter.nvim",
    keys = {
      {"<leader>`", ":Format<CR>", desc = "Format", mode = "n"}
    },
    config = function()
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
            function()
              return {
                exe = "luafmt",
                args = {"--indent-count", 2, "--stdin"},
                stdin = true
              }
            end
          },
          rust = {
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
        }
      }
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
        on_attach = function(client, bufnr)
          -- enable completion triggered by <c-x><c-o>
          vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
          local opts = {noremap = true, silent = true}

          vim.keymap.set("n", "<leader>t", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "<leader>d", vim.lsp.buf.declaration, opts)
          vim.keymap.set("n", "<leader>r", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, opts)

          vim.keymap.set("n", "<leader>i", vim.diagnostic.setloclist, opts)
          vim.keymap.set("n", "[e", vim.diagnostic.goto_prev, opts)
          vim.keymap.set("n", "]e", vim.diagnostic.goto_next, opts)
          vim.keymap.set(
            "n",
            "<leader>f",
            function()
              vim.lsp.buf.format({async = true})
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
                if cmp.visible() then
                  cmp.select_next_item()
                elseif has_words_before() then
                  cmp.complete()
                else
                  fallback()
                end
              end,
              {"i", "s"}
            ),
            ["<S-Tab>"] = cmp.mapping(
              function()
                if cmp.visible() then
                  cmp.select_prev_item()
                else
                  fallback()
                end
              end,
              {"i", "s"}
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
            ---@param adapter CodeCompanion.Adapter
            ---@return string
            system_prompt = function(adapter)
              -- if adapter.schema.model.default == "llama3.1:latest" then
              --   return "My custom system prompt"
              -- end
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
  -- {
  --   "frankroeder/parrot.nvim",
  --   dependencies = {"ibhagwan/fzf-lua", "nvim-lua/plenary.nvim", "rcarriga/nvim-notify"},
  --   keys = {
  --     {"<leader>cn", "<cmd>PrtChatNew<cr>", mode = {"n", "v"}, desc = "New Chat"},
  --     {"<leader>cn", ":<C-u>'<,'>PrtChatNew<cr>", mode = {"v"}, desc = "Visual Chat New"},
  --     {"<leader>cp", ":<C-u>'<,'>PrtChatPaste vsplit<cr>", mode = {"v"}, desc = "paste stuff into parrot chat"},
  --     {"<leader>cc", "<cmd>PrtChatToggle<cr>", mode = {"n"}, desc = "Toggle Popup Chat"},
  --     {"<leader>cr", "<cmd>PrtRewrite<cr>", mode = {"n"}, desc = "Inline Rewrite"},
  --     {"<leader>cr", ":<C-u>'<,'>PrtRewrite<cr>", mode = {"v"}, desc = "Visual Rewrite"},
  --     {"<leader>co", "<cmd>PrtAppend<cr>", mode = {"n"}, desc = "Append"},
  --     {"<leader>co", ":<C-u>'<,'>PrtAppend<cr>", mode = {"v"}, desc = "Visual Append"},
  --     {"<leader>cO", "<cmd>PrtPrepend<cr>", mode = {"n"}, desc = "Prepend"},
  --     {"<leader>cO", ":<C-u>'<,'>PrtPrepend<cr>", mode = {"v"}, desc = "Visual Prepend"},
  --     {"<leader>cs", "<cmd>PrtStop<cr>", mode = {"n", "v", "x"}, desc = "Stop"},
  --     {"<leader>cx", "<cmd>PrtContext<cr>", mode = {"n"}, desc = "Open context file"},
  --     {"<leader>cm", "<cmd>PrtModel<cr>", mode = {"n"}, desc = "Select model"},
  --     {"<leader>cP", "<cmd>PrtProvider<cr>", mode = {"n"}, desc = "Select provider"}
  --   },
  --   -- optionally include "rcarriga/nvim-notify" for beautiful notifications
  --   config = function()
  --     require("parrot").setup {
  --       providers = {
  --         anthropic = {
  --           api_key = os.getenv "ANTHROPIC_API_KEY"
  --         }
  --         -- ollama = {}
  --       },
  --       chat_shortcut_respond = {modes = {"n"}, shortcut = "<cr>"},
  --       chat_shortcut_delete = {modes = {"n"}, shortcut = "<leader>d"},
  --       chat_shortcut_stop = {modes = {"n"}, shortcut = "<leader>s"},
  --       chat_shortcut_new = {modes = {"n"}, shortcut = "<leader>n"},
  --       user_input_ui = "buffer"
  --     }
  --   end
  -- },
  -- {
  --   "magicalne/nvim.ai",
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --     "nvim-treesitter/nvim-treesitter"
  --   },
  --   opts = {
  --     provider = "anthropic", -- you can configure your provider, model or keymaps here.
  --     ollama = {
  --       endpoint = "http://localhost:11434",
  --       model = "llama3.1",
  --       temperature = 0,
  --       max_tokens = 128000,
  --       ["local"] = true
  --     },
  --     -- keymaps
  --     keymaps = {
  --       toggle = "<leader>c", -- toggle chat dialog
  --       send = "<cr>", -- send message in normal mode
  --       close = "q", -- close chat dialog
  --       clear = "<c-l>", -- clear chat history
  --       previous_chat = "[c", -- open previous chat from history
  --       next_chat = "]c", -- open next chat from history
  --       inline_assist = "<leader>i" -- run inlineassist command with prompt
  --     }
  --   }
  -- },
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    opts = {
      provider = "anthropic",
      auto_suggestions_provider = "anthropic",
      system_prompt = llm_default_prompt
    }, -- set this if you want to always pull the latest change
    opts = {},
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = "make",
    -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      -- below are optional
      "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
      "zbirenbaum/copilot.lua", -- for providers='copilot'
      -- {
      --   -- support for image pasting
      --   "HakonHarnes/img-clip.nvim",
      --   event = "VeryLazy",
      --   opts = {
      --     -- recommended settings
      --     default = {
      --       embed_image_as_base64 = false,
      --       prompt_for_file_name = false,
      --       drag_and_drop = {
      --         insert_mode = true
      --       },
      --       -- required for Windows users
      --       use_absolute_path = true
      --     }
      --   }
      -- },
      {
        -- Make sure to set this up properly if you have lazy=true
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
  {
    "hashivim/vim-terraform"
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
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
                ["]m"] = "@function.outer",
                ["]]"] = "@class.outer"
              },
              goto_next_end = {
                ["]m"] = "@function.outer",
                ["]["] = "@class.outer"
              },
              goto_previous_start = {
                ["[m"] = "@function.outer",
                ["[["] = "@class.outer"
              },
              goto_previous_end = {
                ["[m"] = "@function.outer",
                ["[]"] = "@class.outer"
              }
            },
            swap = {
              enable = true,
              swap_next = {
                ["<leader>a"] = "@parameter.inner"
              },
              swap_previous = {
                ["<leader>a"] = "@parameter.inner"
              }
            }
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
      )
    end
  }
}
