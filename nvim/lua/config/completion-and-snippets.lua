-- borrows heavily from
-- https://github.com/MunifTanjim/dotfiles/tree/3d81d787b5a7a745598e623d6cdbd61fb10cef97/private_dot_config/nvim/lua/plugins

-- luasnip setup
-- local luasnip = require "luasnip"
local lspkind = require("lspkind")

local has_words_before = function()
  if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
    return false
  end
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

-- nvim-cmp setup
local cmp = require "cmp"

vim.o.completeopt = "menu,menuone,noselect"
cmp.setup {
  -- snippet = {
  --   expand = function(args)
  --     require("luasnip").lsp_expand(args.body)
  --   end
  -- },
  -- completion = {
  --   autocomplete =
  --   completeopt = vim.o.completeopt
  -- },
  -- exprimental = {
  --   ghost_text = true
  -- },
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

-- cmp.setup.cmdline(
--   "/",
--   {
--     mapping = cmp.mapping.preset.cmdline(),
--     sources = {
--       {name = "buffer"}
--     }
--   }
-- )
--
-- cmp.setup.cmdline(
--   ":",
--   {
--     sources = cmp.config.sources(
--       {
--         {name = "path"}
--       },
--       {
--         {name = "cmdline"}
--       }
--     )
--   }
-- )

-- cmp.event:on(
--   "menu_opened",
--   function()
--     vim.b.copilot_suggestion_hidden = true
--   end
-- )
--
-- cmp.event:on(
--   "menu_closed",
--   function()
--     vim.b.copilot_suggestion_hidden = false
--   end
-- )
--
-- require("copilot").setup(
--   {
--     panel = {
--       auto_refresh = false,
--       keymap = {
--         accept = "<CR>",
--         jump_prev = "[[",
--         jump_next = "]]",
--         refresh = "gr",
--         open = "<M-CR>"
--       }
--     },
--     suggestion = {
--       auto_trigger = false,
--       keymap = {
--         accept = false,
--         accept_word = "<M-Right>",
--         accept_line = "<M-Down>",
--         prev = "<M-[>",
--         next = "<M-]>",
--         dismiss = "<C-]>"
--       }
--     }
--   }
-- )
--
-- local suggestion = require("copilot.suggestion")

---@param mode string|string[]
---@param lhs string
---@param rhs string|fun():nil
---@param desc_or_opts string|table
---@param opts? table
function set_keymap(mode, lhs, rhs, desc_or_opts, opts)
  if not opts then
    opts = type(desc_or_opts) == "table" and desc_or_opts or {desc = desc_or_opts}
  else
    opts.desc = desc_or_opts
  end
  vim.keymap.set(mode, lhs, rhs, opts)
end

-- set_keymap(
--   "i",
--   "<M-l>",
--   function()
--     if suggestion.is_visible() then
--       suggestion.accept()
--     else
--       suggestion.next()
--     end
--   end,
--   "[copilot] accept or next suggestion"
-- )
--

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

-- init CopilotChat
-- require("CopilotChat").setup {
--   prompts = {
--     Explain = {
--       prompt = "/COPILOT_EXPLAIN Write an explanation for the active selection as paragraphs of text.",
--       mapping = "<leader>ce",
--       description = "Explain how the selection works.",
--       selection = require("CopilotChat.select").visual
--     }
--   },
--   mappings = {
--     reset = {
--       normal = "<C-r>",
--       insert = "<C-r>"
--     }
--   },
--   window = {
--     width = 0.5,
--     height = 0.5
--   }
-- }
--
-- -- keybindings for neovim CopilotChat
-- set_keymap(
--   "n",
--   "<leader>cc",
--   function()
--     require("CopilotChat").toggle()
--   end,
--   "toggle CopilotChat"
-- )
--
-- set_keymap(
--   "n",
--   "<leader>cq",
--   function()
--     local input = vim.fn.input("Quick Chat: ")
--     if input ~= "" then
--       require("CopilotChat").ask(input, {selection = require("CopilotChat.select").line})
--     end
--   end,
--   "ask a quick question about the currentl line"
-- )
--
-- set_keymap(
--   "v",
--   "<leader>cq",
--   function()
--     local input = vim.fn.input("Quick Chat: ")
--     if input ~= "" then
--       require("CopilotChat").ask(input, {selection = require("CopilotChat.select").visual})
--     end
--   end,
--   "ask a quick question about the currentl line"
-- )
