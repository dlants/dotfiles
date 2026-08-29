-- Send a glean review to magenta as structured data rather than rendered prose.
--
-- Overrides <leader>mb (magenta's "add buffer to context") with a buffer-local
-- binding inside glean buffers, where adding the buffer itself would just hand
-- the agent rendered prose. Instead we paste the exact `glean.api` call and its
-- JSON result, so the agent can reply immediately without re-deriving session
-- and comment ids or re-fetching the same comments.
local M = {}

-- The "gN" id of the review rendered in `bufnr`, or nil if it isn't a live one.
-- The api addresses reviews by this string, and it goes into the pasted command.
local function session_id(bufnr)
  for _, s in ipairs(require("glean.init").live_sessions()) do
    if s.buf == bufnr then return s.id end
  end
end

-- The one-line provenance the excerpt is meaningless without: which review, in
-- which repo, over which range. `WORKTREE` is glean's sentinel target, so spell
-- it as what it actually is.
local function describe(id)
  for _, s in ipairs(require("glean.api").sessions()) do
    if s.id == id then
      local target = s.target == "WORKTREE" and "the work tree" or s.target
      return ("Glean review %s — %s, %s..%s (%s scope)")
        :format(s.id, vim.fn.fnamemodify(s.repo, ":t"), s.base, target, s.scope)
    end
  end
  return ("Glean review %s"):format(id)
end
-- One JSON object per line inside a literal array: valid JSON, but readable and
-- diffable in the input buffer. Neovim has no pretty-printer.
local function encode(comments)
  local lines = {}
  for i, c in ipairs(comments) do
    lines[i] = vim.json.encode(c)
  end
  return "[\n" .. table.concat(lines, ",\n") .. "\n]"
end

local function build_text(id, comments)
  return table.concat({
    describe(id) .. " — comments:",
    "",
    "```",
    (':lua require("glean.api").comments("%s")'):format(id),
    encode(comments),
    "```",
    "",
    ('Reply with require("glean.api").reply("%s", <id>, <text>). See the glean-review skill for other commands.')
      :format(id),
  }, "\n")
end

-- Route through `:Magenta paste`, which opens the sidebar if needed and appends
-- to the active thread's input buffer. It reads register + synchronously, so we
-- can borrow the register and hand it straight back.
local function paste(text)
  local saved, savedtype = vim.fn.getreg("+"), vim.fn.getregtype("+")
  vim.fn.setreg("+", text, "l")
  local ok, err = pcall(vim.cmd, "Magenta paste")
  vim.fn.setreg("+", saved, savedtype)
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end

local function send_comments()
  local id = session_id(vim.api.nvim_get_current_buf())
  if not id then
    vim.notify("glean: this buffer is not a live review", vim.log.levels.WARN)
    return
  end
  local ok, comments = pcall(require("glean.api").comments, id)
  if not ok then
    vim.notify(tostring(comments), vim.log.levels.ERROR)
    return
  end
  if #comments == 0 then
    vim.notify(("glean: %s has no comments"):format(id), vim.log.levels.INFO)
    return
  end
  paste(build_text(id, comments))
end

-- Overrides visual <leader>mp (magenta's "send selection") the same way, and for
-- the same reason: the raw buffer lines are rendered prose — virtual +/- markers,
-- marker rows, headers — under a `glean://` name the agent cannot open. Ask
-- glean for the diff its rows stand for instead. The selection is taken
-- linewise; a partial-line selection just means its whole lines.

local function send_selection()
  local id = session_id(vim.api.nvim_get_current_buf())
  if not id then
    vim.notify("glean: this buffer is not a live review", vim.log.levels.WARN)
    return
  end
  local srow, erow = vim.fn.line("v"), vim.fn.line(".")
  vim.cmd("normal! \27")
  local ok, text = pcall(require("glean.api").excerpt, id, srow, erow)
  if not ok then
    vim.notify(tostring(text), vim.log.levels.ERROR)
    return
  end
  if text == "" then
    vim.notify("glean: the selection holds no diff lines", vim.log.levels.WARN)
    return
  end
  paste(describe(id) .. " — selected diff:\n\n```diff\n" .. text .. "\n```")
end

function M.setup()
  local function bind(bufnr)
    vim.keymap.set("n", "<leader>mb", send_comments, {
      buffer = bufnr,
      silent = true,
      noremap = true,
      desc = "Send glean review comments to Magenta",
    })
    vim.keymap.set("x", "<leader>mp", send_selection, {
      buffer = bufnr,
      silent = true,
      noremap = true,
      desc = "Send the selected diff to Magenta",
    })
  end
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "glean",
    callback = function(args) bind(args.buf) end,
  })
  -- Reloading this module mid-session shouldn't leave open reviews unbound.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "glean" then bind(buf) end
  end
end

return M
