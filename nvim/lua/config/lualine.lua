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
    lualine_c = {{"filename", path = 1}},
    lualine_x = {"filetype"},
    lualine_y = {"branch"},
    lualine_z = {"diff"}
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {{"filename", path = 1}},
    lualine_x = {},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {},
  extensions = {}
}
