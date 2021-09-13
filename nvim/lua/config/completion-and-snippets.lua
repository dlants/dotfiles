local luasnip = require "luasnip"
local types = require "cmp.types"
local compare = require "cmp.config.compare"
local cmp = require "cmp"

vim.o.completeopt = "menuone,noselect,noinsert"

local WIDE_HEIGHT = 40

-- borrows from luasnip example https://github.com/hrsh7th/nvim-cmp/wiki/Example-mappings
local has_words_before = function()
  if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
    return false
  end
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local feedkey = function(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, true, true), "n", true)
end

cmp.setup {
  enabled = function()
    return vim.api.nvim_buf_get_option(0, "buftype") ~= "prompt"
  end,
  completion = {
    autocomplete = {
      types.cmp.TriggerEvent.TextChanged
    },
    completeopt = "menu,menuone,noselect",
    keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%(-\w*\)*\)]],
    keyword_length = 1,
    get_trigger_characters = function(trigger_characters)
      return trigger_characters
    end
  },
  snippet = {
    expand = function()
      error("snippet engine is not configured.")
    end
  },
  preselect = types.cmp.PreselectMode.Item,
  documentation = {
    border = {"", "", "", " ", "", "", "", " "},
    winhighlight = "NormalFloat:CmpDocumentation,FloatBorder:CmpDocumentationBorder",
    maxwidth = math.floor((WIDE_HEIGHT * 2) * (vim.o.columns / (WIDE_HEIGHT * 2 * 16 / 9))),
    maxheight = math.floor(WIDE_HEIGHT * (WIDE_HEIGHT / vim.o.lines))
  },
  confirmation = {
    default_behavior = types.cmp.ConfirmBehavior.Insert,
    get_commit_characters = function(commit_characters)
      return commit_characters
    end
  },
  sorting = {
    priority_weight = 2,
    comparators = {
      compare.offset,
      compare.exact,
      compare.score,
      compare.kind,
      compare.sort_text,
      compare.length,
      compare.order
    }
  },
  event = {},
  mapping = {
    ["<Tab>"] = cmp.mapping(
      function(fallback)
        if vim.fn.pumvisible() == 1 then
          feedkey("<C-n>")
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        elseif has_words_before() then
          cmp.complete()
        else
          fallback() -- The fallback function sends a already mapped key. In this case, it's probably `<Tab>`.
        end
      end,
      {"i", "s"}
    ),
    ["<S-Tab>"] = cmp.mapping(
      function(fallback)
        if vim.fn.pumvisible() == 1 then
          feedkey("<C-p>")
        elseif luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end,
      {"i", "s"}
    )
  },
  formatting = {
    deprecated = true,
    format = function(_, vim_item)
      return vim_item
    end
  },
  experimental = {
    ghost_text = false
  },
  sources = {
    {name = 'nvim_lsp'},
    {name = 'buffer'},
    {name = 'path'},
  }
}
