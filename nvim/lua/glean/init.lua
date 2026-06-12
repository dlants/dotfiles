-- glean: review the diff between two git refs in a single foldable buffer.
--
-- Stage 2 renders the *combined* scope (`base...target`) into one nofile
-- buffer. The model (an ordered list of FileEntries from glean.git) is the
-- single source of truth; the buffer is a pure projection of it. A parallel
-- `row_map[row]` resolves any cursor row back to its file/hunk/line so actions
-- can act on the semantic target. Collapse is ephemeral session view-state: a
-- collapsed file simply omits its body on the next render.
local git_mod = require("glean.git")
local M = {}
local api = vim.api
local NS = api.nvim_create_namespace("glean_hl")

M.config = {
  default_base = "main",
}

-- A Session owns one review buffer: the git handle, the rendered FileEntries,
-- and the row_map projecting buffer rows back onto the model.
local Session = {}
Session.__index = Session

local CHEVRON_OPEN = "▾"
local CHEVRON_CLOSED = "▸"

-- Build the lines and the parallel row_map for the current model state. Pure:
-- returns { lines, row_map, highlights } without touching any buffer.
function Session:build()
  local lines = {}
  local row_map = {}
  local highlights = {}
  local function emit(text, target, hl)
    lines[#lines + 1] = text
    local row = #lines - 1
    row_map[row] = target
    if hl then highlights[#highlights + 1] = { row = row, hl = hl } end
    return row
  end
  for fi, file in ipairs(self.files) do
    local chevron = file.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
    local kind = file.kind and (" [" .. file.kind .. "]") or ""
    emit(chevron .. " " .. file.path .. kind, { file = fi }, "GleanFileHeader")
    if not file.collapsed then
      for hi, hunk in ipairs(file.hunks) do
        emit(hunk.header, { file = fi, hunk = hi }, "GleanHunkHeader")
        for li, dl in ipairs(hunk.lines) do
          local marker = dl.kind == "add" and "+"
            or dl.kind == "del" and "-"
            or " "
          local hl = dl.kind == "add" and "GleanAdd"
            or dl.kind == "del" and "GleanDel"
            or "GleanContext"
          emit(marker .. dl.text, { file = fi, hunk = hi, line = li }, hl)
        end
      end
    end
  end
  return lines, row_map, highlights
end

-- Re-render the buffer from the model, preserving cursor row when possible.
function Session:render()
  local lines, row_map, highlights = self:build()
  self.row_map = row_map
  local win = self.win
  local cur
  if win and api.nvim_win_is_valid(win) then
    cur = api.nvim_win_get_cursor(win)
  end
  api.nvim_set_option_value("modifiable", true, { buf = self.buf })
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = self.buf })
  api.nvim_buf_clear_namespace(self.buf, NS, 0, -1)
  for _, h in ipairs(highlights) do
    api.nvim_buf_set_extmark(self.buf, NS, h.row, 0, {
      end_row = h.row + 1,
      end_col = 0,
      hl_group = h.hl,
      hl_eol = true,
    })
  end
  if cur then
    local last = math.max(1, #lines)
    cur[1] = math.min(cur[1], last)
    pcall(api.nvim_win_set_cursor, win, cur)
  end
end

-- Toggle the collapsed flag of the file owning `row` (defaults to cursor row),
-- then re-render. Collapse is ephemeral view-state — never persisted.
function Session:toggle_collapse(row)
  if row == nil and self.win and api.nvim_win_is_valid(self.win) then
    row = api.nvim_win_get_cursor(self.win)[1] - 1
  end
  local target = self.row_map[row]
  if not target then return end
  local file = self.files[target.file]
  file.collapsed = not file.collapsed
  self:render()
end

local function setup_keymaps(buf, session)
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("=", function() session:toggle_collapse() end)
  map("q", function()
    if api.nvim_win_is_valid(session.win) then
      api.nvim_win_close(session.win, true)
    end
  end)
end

-- Open a review of `base...target` (combined scope). `opts`:
--   - base, target (required): refs to diff.
--   - repo_root (optional): overridden in tests; discovered otherwise.
--   - run (optional): injected git runner (tests).
--   - open_window (optional, default true): create a split window. Tests that
--     only inspect buffer state can pass false.
-- Returns the Session (with `.buf`, `.row_map`, `:toggle_collapse`).
function M.open(opts)
  assert(opts and opts.base and opts.target, "glean.open requires base and target")
  local repo_root = opts.repo_root
    or git_mod.discover_repo_root(api.nvim_buf_get_name(0))
  assert(repo_root, "glean: could not find a git repo root")
  local git = git_mod.new({ repo_root = repo_root, run = opts.run })
  local files, err = git:combined_diff(opts.base, opts.target)
  if not files then error("glean: combined_diff failed: " .. tostring(err)) end
  for _, f in ipairs(files) do f.collapsed = false end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_set_option_value("filetype", "glean", { buf = buf })
  pcall(api.nvim_buf_set_name, buf, "glean://" .. buf .. ":" .. opts.base .. "..." .. opts.target)

  local session = setmetatable({
    git = git,
    base = opts.base,
    target = opts.target,
    files = files,
    buf = buf,
    win = nil,
    row_map = {},
  }, Session)

  local open_window = opts.open_window ~= false
  if open_window then
    vim.cmd("tabnew")
    session.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(session.win, buf)
    setup_keymaps(buf, session)
  end

  session:render()
  return session
end

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
  api.nvim_set_hl(0, "GleanFileHeader", { link = "Title", default = true })
  api.nvim_set_hl(0, "GleanHunkHeader", { link = "Comment", default = true })
  api.nvim_set_hl(0, "GleanAdd", { link = "DiffAdd", default = true })
  api.nvim_set_hl(0, "GleanDel", { link = "DiffDelete", default = true })
  api.nvim_set_hl(0, "GleanContext", { link = "Normal", default = true })
  api.nvim_create_user_command("Glean", function(o)
    local args = o.fargs
    local base = args[1] or M.config.default_base
    local target = args[2] or "HEAD"
    M.open({ base = base, target = target })
  end, { nargs = "*" })
end

return M
