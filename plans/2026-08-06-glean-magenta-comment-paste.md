# Objective and Context

> I think on `<leader>mb`, when we're inside a glean buffer, I want to paste the output of listing that specific session.
>
> Let's add this override in my own dotfiles (`~/src/dotfiles/nvim`), instead of magenta.nvim
>
> This should go into the magenta input buffer for the current thread, and open it if it's not open (like `<leader>mb` inside magenta does).
>
> The text should show the lua command we would run to get the output, and the (structured) output.

Today the flow is: yank rendered comment prose out of the glean buffer, `<leader>mp` it into magenta, and let the agent reverse-engineer the session id from the buffer name and the comment ids from `[7]` tags — after which it usually calls `glean.api.comments()` anyway, fetching a second copy of everything. This replaces that with a single structured paste.

Entities involved:

- `require("glean.api")` (`~/src/glean/lua/glean/api.lua`) — the flat JSON-only surface.
  - `sessions() -> { {id, repo, base, target, scope, title}, ... }`
  - `session(id_or_bufnr) -> Session` — accepts a **buffer number** as well as a `"g1"` id (`api.lua:46`, `s.id == id or s.buf == id`), and errors loudly rather than returning nil.
  - `comments(session, opts) -> { {id, path, lnum, side, text, reply, content, code, outdated}, ... }` with `opts = { unanswered = bool, path = string }`.
  - `reply(session, id, text)` / `unreply(session, id)`.
- `require("glean.init").live_sessions()` — the live `Session` list; each has `.id` and `.buf`. This is how we map "the buffer I am standing in" to the `"g1"` string we must print in the reproducible lua command.
- `:Magenta paste` (`~/src/magenta.nvim/lua/magenta/init.lua:250`) — the one command that puts arbitrary text into the input buffer. It is special-cased in the `:Magenta` dispatcher to run `require("magenta.keymaps").do_paste()` in-process, which reads register `+` and forwards it to node as `magentaClipboardTextPaste` → `pasteIntoActiveInputBuffer` (`node/magenta.ts:1109`), which **opens the sidebar if it isn't visible** and appends to the active thread's input buffer. That is exactly the "open it if it's not open" behavior asked for, already implemented.
- `:Magenta paste-selection` — the other paste entry point, but it reads the visual marks of the *current* buffer, so it can only send text that is literally in a buffer. Not usable here.
- `~/src/dotfiles/nvim/init.lua:216` — `require("glean.init").setup()`; the natural place to hook in.
- `~/src/dotfiles/nvim/lua/config/plugins.lua:19-36` — where `magenta.setup()` runs, including `default_keymaps` (global `<leader>mb` → `add_buffer_to_context`).

Relevant files:

- `nvim/lua/config/glean.lua` — **new**; the whole feature.
- `nvim/init.lua` — one line to call its `setup()`.

# Design

A `FileType glean` autocmd installs a **buffer-local** `<leader>mb`. Buffer-local keymaps take precedence over magenta's global one, so no magenta code changes and the default binding is untouched everywhere else.

The handler:

1. Resolves the current buffer to a session id by scanning `glean.init.live_sessions()` for `s.buf == bufnr`. We need the _string_ id (not just the Session) because it goes into the printed command. If no match (e.g. a stale glean-filetype buffer), notify and bail.
2. Calls `require("glean.api").comments(id)`, wrapped in `pcall` so a glean error surfaces as a notification instead of a keymap traceback.
3. If the result is empty, notify "no comments" and paste nothing. Pasting an empty array into the input buffer is pure noise.
4. Builds the block, stashes it in register `+` (saving and restoring the previous contents and regtype around the call), and runs `vim.cmd("Magenta paste")`.

Pasted text shape — the command first, so the agent knows the payload is a faithful, reproducible `api` result and can re-run it later (e.g. after answering some) rather than re-deriving it. The example below is verbatim what lands in the input buffer (indented here by four spaces only so the inner fences survive this document):

    Glean review comments — session g1:

    ```
    :lua require("glean.api").comments("g1")
    [
    {"id":3,"path":"lua/glean/init.lua","lnum":412,"side":"new","text":"why is this recomputing row_map on every render? seems like it could be cached","content":["+  local map = build_row_map(model)","+  vim.b[buf].glean_rows = map"],"code":"+  local map = build_row_map(model)\n+  vim.b[buf].glean_rows = map","outdated":false},
    {"id":7,"path":"lua/glean/state.lua","lnum":88,"side":"old","text":"this drops the sticky override silently when the shard is missing","reply":"fixed in 3a91c2f — load_shard now errors on a malformed shard and only returns {} for a genuinely absent one.","content":["-  store.overrides = load_shard(sha) or {}"],"code":"-  store.overrides = load_shard(sha) or {}","outdated":true}
    ]
    ```

    Reply with require("glean.api").reply("g1", <id>, <text>). See the glean-review skill for other commands.

Notes on the payload, all consequences of `vim.json.encode` on the raw `api.comments` records:

- `reply` is absent (not `null`) on unanswered comments — a lua `nil` field simply doesn't encode. Already-answered comments carry `"reply":"..."`, which is exactly the signal the agent needs to skip them.
- `lnum` may likewise be absent when a comment has no resolved diff line.
- `code` is `content` joined with newlines, so the two are redundant; both are included anyway because that is what the api returns, and the invariant is that the pasted JSON is exactly the command's output.
- `outdated:true` means the anchored code no longer matches the diff — the agent should treat that comment's `code` as historical.

Formatting choice: `vim.json.encode` each comment separately and join with `",\n"` inside literal `[`/`]` lines. Neovim has no pretty-printer, and one-object-per-line keeps it diffable and readable in the input buffer while staying valid JSON. `vim.inspect` was considered — it would match the lua command's actual return value more literally — but the api is documented as JSON-only and the agent's other view of this data (via `nvim_exec_lua`) is JSON, so JSON keeps one representation.

Send **all** comments, not just unanswered ones: the answered ones are cheap, and their `reply` text is context the agent would otherwise have to re-fetch to know what was already said. The `unanswered` filter stays available in `api` for the agent's own follow-up calls.

Invariants:

- The printed lua command must be exactly what produced the pasted JSON — if the opts change, the printed string changes with it. A drifting command is worse than no command.
- The buffer-local map must not disturb magenta's global `<leader>mb` in any other buffer.
- No glean internals beyond `live_sessions()` are touched; all comment data comes through `api`, so the agent's later `api` calls see the same shape.
- Nothing is pasted on the empty/error paths.
- Register `+` is borrowed, not stolen: its previous contents and regtype are restored immediately after `:Magenta paste` returns (`do_paste` reads the register synchronously before notifying node, so this is safe).
- Failure modes notify and return; never throw out of a keymap.

# Stages

## the dotfiles module

- Goal: `<leader>mb` in a glean buffer opens the magenta sidebar (if closed) and appends the command + JSON block for all of that session's comments. `<leader>mb` elsewhere still adds the buffer to context.
- Implementation: `nvim/lua/config/glean.lua` exposing `setup()`, called from `init.lua` after `require("glean.init").setup()`.
- Tests: dotfiles has no lua test harness, so this is verified by hand in a live session:
  - Open a review with `:Glean`, add two comments, answer one via `api.reply`. Press `<leader>mb` with the sidebar **closed**: the sidebar opens and the input buffer holds a block with both comments, the answered one carrying its `reply`, and the session id in the printed command matching the buffer name's `Glean:gN`.
  - Press it again with the sidebar already open: block is appended, sidebar is not re-toggled.
  - With two reviews open simultaneously, each buffer's binding emits its own session id — this is the case the old paste-the-prose flow got wrong most often.
  - In a normal source buffer, `<leader>mb` still adds the buffer to magenta context.
  - With no comments in the review: a notification, and the input buffer is unchanged.
  - With magenta's node process not started: `:Magenta paste` no-ops with magenta's own "input buffer not ready" message; we don't add our own handling.
  - After a paste, register `+` (and the system clipboard) holds whatever it held before.

## skill wording

- Goal: the agent stops double-fetching.
- Add a line to `~/src/glean/skills/glean-review/skill.md`: when a `Glean review comments` block is present in the conversation, treat it as the complete, current comment set — do not call `api.comments()` again unless replies have since been written and you need to re-check state.
- Tests: run a real review round-trip and confirm the agent's first tool call is `reply`, not `comments`.
