vim.keymap.set(
  "n",
  "<leader>pr",
  function()
    vim.cmd("UpdateRemotePlugins")
    vim.cmd("runtime plugin/magenta.vim")
  end,
  {desc = "Reload magenta plugin"}
)

_G.P = function(v)
  print(vim.inspect(v))
  return v
end

vim.keymap.set(
  "n",
  "<leader>t",
  function()
    local plenary = require("plenary.test_harness")
    plenary.test_directory(vim.fn.expand("%:p"))
  end,
  {desc = "Run plenary test under cursor"}
)

function DebugExtmarks(namespace)
  local ns = type(namespace) == "string" and vim.api.nvim_create_namespace(namespace) or namespace

  local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
  for _, mark in ipairs(marks) do
    local id, row, col = unpack(mark)
    vim.api.nvim_buf_set_extmark(
      0,
      ns,
      row,
      col,
      {
        virt_text = {{string.format("[mark %d]", id), "Comment"}},
        virt_text_pos = "inline"
      }
    )
  end
end

-- function asdf()
--   vim.api.nvim_buf_set_lines(0, 0, -1, false, {"⚙️hello", "⚙️hello", "⚙️hello"})
--   vim.api.nvim_buf_set_text(0, 0, 0, 0, 1, {"✅"})
--   vim.api.nvim_buf_set_text(0, 1, 0, 1, 2, {"✅"})
--   vim.api.nvim_buf_set_text(0, 2, 0, 2, 3, {"✅"})
--   local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false )
--   print(vim.inspect(lines))
-- end
--

function GetLineWidth()
  return #(vim.api.nvim_buf_get_lines(0, 2, 3, false)[1])
end

function testSelection()
  vim.api.nvim_win_set_cursor(0, {1, 1})
  vim.api.nvim_exec2("normal!v", {})
  vim.api.nvim_win_set_cursor(0, {2, 1})
end

function testAttach()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)

  print("Tracking edits for buffer " .. bufnr .. " (" .. bufname .. ")")

  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _, _, firstline_0idx, lastline_0idx_excl, new_lastline_0idx_excl)
      -- Print the event immediately
      local event = {
        firstline_0idx = firstline_0idx,
        lastline_0idx_excl = lastline_0idx_excl,
        new_lastline_0idx_excl = new_lastline_0idx_excl
      }

      print("on_lines event: " .. vim.inspect(event))

      return false -- Keep attached
    end
  })

  print("Tracker attached. Edit the buffer to see events.")
end

function CustomTMotion()
  local function create_mapping()
    local char = vim.fn.getchar()

    if type(char) == "number" then
      char = vim.fn.nr2char(char)
    end

    local line = vim.api.nvim_get_current_line()

    local last_pos = line:find(vim.pesc(char), 1, true)
    local current_pos = last_pos

    while current_pos do
      last_pos = current_pos
      current_pos = line:find(vim.pesc(char), last_pos + 1, true)
    end

    if last_pos then
      local row = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_win_set_cursor(0, {row, last_pos - 1})
      return true
    end

    return false
  end

  return create_mapping
end

vim.keymap.set({'n', 'x', 'o'}, 'T', function()
  return CustomTMotion()()
end, {expr = false, desc = "Move to last occurrence of character in line"})
