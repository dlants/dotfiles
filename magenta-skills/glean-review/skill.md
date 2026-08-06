---
name: glean-review
description: Reading and responding to comments in an open glean review (the neovim git diff reviewer). Use this when the user pastes a glean review snippet, asks you to answer review comments, or mentions a `Glean:` buffer.
---

# glean review comments

glean renders a git diff into a neovim buffer. The human leaves comments on
lines; you answer them. Drive it with the `nvim_lua` tool through
`require("glean.api")` — everything crosses the boundary as plain strings and
numbers, so each call is self-contained and there is no handle to keep.

## The model

A comment has exactly two slots:

- `text` — the human's words. **You never write this.** There is no api to add,
  edit or delete a comment; that is the human's buffer, and their keymaps.
- `reply` — your answer. At most one per comment, and replying again replaces
  the previous one, so re-running over the same review is idempotent. `reply`
  is `nil` when the comment is unanswered — that is your work queue.

Each comment also reports `id`, `path`, `lnum`, `side` (`"new"` for
adds/context, `"old"` for deletions), `content` (the diff-line block captured
when the comment was written, as a list), `code` (the same block joined), and
`outdated` (true when that block no longer matches the diff, i.e. the code moved
out from under the comment — say so in your reply rather than guessing).

## Recovering ids from a paste

Two ids address any comment, and both are visible in the review buffer, so a
pasted snippet is a sufficient address.

- **Session id** — in the buffer name: `Glean:g2 glean main [8df5247a..09997456]`
  → the session is `"g2"`. Pass `nil` when only one review is open.
- **Comment id** — the bracketed token of a comment row: `💬 [7] why is this
  needed?` → the comment is `7` (a number, not a string). The same `[7]` token
  appears in the review's comments summary section. Your reply renders beneath
  the comment as an indented `↳` block.

## Entry points

List the open reviews:

```lua
return require("glean.api").sessions()
-- { { id = "g1", repo = "/path/to/repo", base = "...", target = "...",
--     scope = "combined", title = ".../Glean:g1 repo main" } }
-- `title` is the raw buffer name, so it may carry a directory prefix; the
-- session id is the `g<N>` right after `Glean:`.
```

List comments (`session` may be `nil` with one review open):

```lua
return require("glean.api").comments("g1")
```

Just the ones needing an answer, optionally scoped to a file:

```lua
return require("glean.api").comments("g1", { unanswered = true, path = "lua/glean/init.lua" })
```

Answer one, and clear an answer:

```lua
return require("glean.api").reply("g1", 7, "Yes — the guard is needed because ...")
```

```lua
return require("glean.api").unreply("g1", 7)
```

Replies are undoable (`u` in the review buffer), persist to glean's store, and
re-render immediately, so the human watches your answers land live.

## Errors

Every call errors loudly rather than no-opping:

- no review open → open one with `:Glean` (ask the human; do not try to open it
  yourself, you should answer exactly what they are looking at).
- several reviews open and no `session` → the error lists the candidate ids with
  their repo and range; pick one.
- unknown comment id → re-list with `comments()`; ids are per review.
- `reply` with an empty or non-string text errors; use `unreply` to clear.

## Working a review

1. `comments(session, { unanswered = true })` to get the queue.
2. For each, read the code around `path`:`lnum` before answering — `code` is
   only the anchored block, not the surrounding context.
3. `reply(session, id, ...)` one at a time; keep answers short, since they
   render inline in the diff.
