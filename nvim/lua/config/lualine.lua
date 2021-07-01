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
    lualine_b = {"diagnostics"},
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
