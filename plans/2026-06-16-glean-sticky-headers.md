# Objective and Context

## User request (verbatim)

> I want to update the glean view.
>
> In particular, I want to take advantage of treesitter-context. For example, for markdown files, treesitter-context will show the header stack even as you scroll down through the text of the section, and I think that would be really useful here - to be able to see the header as you navigate down
>
> in general, I think the current layout is a bit difficult to see.
>
> A few ideas:
>
> 1. we could turn the glean buffer into a markdown file, use # headers, which would take advantage of the existing markdown treesitter and treesitter-context
>
> 2. maybe we can provide the AST treesitter-context needs directly?
>
> 3. maybe we can implement the thing that treesitter-context does (hovering headers) ourselves?
>
> Use the thinking subagent to think about this, then give me your recommendations.
>
> write a plan

## What we're building and why

A "sticky header" affordance for the glean review buffer: as the user scrolls
down through a diff, the enclosing structural context (commit header, file
header, seen/unseen section header, hunk header) stays pinned at the top of the
window — the same effect treesitter-context gives for code. This makes deep
hunks legible: you always know which commit / file / hunk the visible lines
belong to.

We implement this ourselves (idea 3) rather than re-rendering glean as markdown
(idea 1) or feeding a synthetic tree to treesitter-context (idea 2). Rationale:

- **Idea 1 rejected**: glean's body rows are *raw source text* from files under
  review, so a file's own `#`, `---`, fenced, or indented lines would be
  misparsed as glean structure. Glean headers also use chevrons / marks / hunk
  `--- @@` lines that collide with markdown syntax, and a markdown highlighter
  would fight the custom `Glean*` extmark highlights.
- **Idea 2 rejected**: treesitter-context has no public injection point — it
  calls `vim.treesitter.get_parser(buf)` and no-ops without a parser — and
  Neovim has no API to synthesize a `TSTree` without a compiled grammar.
  Shipping/compiling a grammar (across macOS + devcontainer, against the
  Nix-pinned tree-sitter) for a frequently-changing internal projection format
  is high-cost and fragile.
- **Idea 3 chosen**: glean already owns its window, a complete row→model
  `row_map`, its highlight groups, and a per-buffer autocmd group. A pinned
  `focusable=false` float built from `row_map` is ~150 lines, couples to nothing
  external, and is exactly the technique treesitter-context uses internally.

## Key entities

- `Session` (in `nvim/lua/glean/init.lua`) — owns `self.buf`, `self.win`, and
  produces the rendered buffer via `Session:build()` / `Session:render()`.
- `row_map` (built in `build()`, line ~518) — 0-indexed row → target descriptor
  (`commit`/`file`/`cfile`/`hunk`/`line`/`marker`/`seen`/`unseen`/`comment`).
- `highlights` array (built in `build()`) — `{row, hl}` extmark specs; the source
  of per-row header highlight groups.
- Header row text shapes (plain text, already rendered): commit `▾ ✓ <sha8> ...`,
  file `  ▾ ✓ <path> [kind]` (or `▾ <path> [kind]` in combined scope), section
  `  ▾ ✓ seen (N hunks)` / `  ▸ ● unseen (N hunks)`, hunk `--- @@ ... @@`.

## Relevant files

- `nvim/lua/glean/init.lua` — all work lands here: `build()` (~516-699),
  `render()` (702-737), buffer/window setup (~1995-2015), highlight groups
  (~2130-2146), the per-buffer cursor augroup `glean_cursor_<buf>`.
- `nvim/lua/glean/init_test.lua` — main test suite; add coverage here.
- `nvim/lua/glean/run_tests.lua` — runner: \`nvim -l nvim/lua/glean/run_tests.lua\`.
- `nvim/lua/config/plugins.lua` — treesitter-context config; add a defensive
  \`on_attach\` opt-out for filetype \`glean\`.

# Design

## Ancestry computation (pure, testable)

Add an O(N) post-pass that runs right after `self.row_map = row_map` in
`render()` (do not modify `build()`). Walking rows top-to-bottom, carry a running
ancestry of the most recent `commit_row`, `file_row`, `sec_row`, `hunk_row`,
clearing deeper levels when a shallower header is seen:

- commit header (`target.commit` set, no file/cfile/sec/hunk) → set commit_row,
  clear file/sec/hunk.
- file header (`target.file` or `target.cfile`, no sec/hunk/line) → set file_row,
  clear sec/hunk.
- section header (`target.seen` or `target.unseen`) → set sec_row, clear hunk.
- hunk header (`target.hunk` set, `target.line == nil`, `target.marker == nil`)
  → set hunk_row.

Store `self.ancestry[row] = { commit_row, file_row, sec_row, hunk_row }` (a
snapshot of the running state at that row) and `self.row_hl[row] = hl` from the
`highlights` array. This classification is the part most worth unit-testing.

Factor the classification into a small pure helper (e.g.
`M.compute_ancestry(row_map, n)` returning the ancestry table) so it can be
tested without a window.

## Pinned set + float rendering

On scroll, let `w0 = vim.fn.line('w0', win) - 1` (0-indexed top visible row).
The pinned rows are `ancestry[w0]` in order `[commit, file, sec, hunk]`, filtered
to `row < w0` (a still-visible header isn't duplicated). Empty chain → close the
float. This filter makes top-of-buffer, the mode header, blank rows, and the
comments section all collapse to "no float" for free.

Render into a reused scratch buffer shown in a reused float:
`nvim_open_win(buf, false, { relative='win', win, anchor='NW', row=0, col=0,
width=<win width>, height=#pinned, focusable=false, noautocmd=true,
style='minimal', zindex=50 })`; reposition/resize via `nvim_win_set_config` on
later updates rather than recreating. Float line text = the exact pinned rows via
`nvim_buf_get_lines(self.buf, row, row+1)`, each prefixed with one space to match
the body's `signcolumn=yes:1` gutter offset; set `wrap=false`. Apply one full-line
extmark per float line using `self.row_hl[row]` (`hl_eol=true`). Headers carry a
single whole-line group and no intraline marks, so no NS_INTRA copying is needed.

## Events and lifecycle

Drive updates from the existing `glean_cursor_<buf>` augroup (cleared on setup,
so reuse is safe):

- `WinScrolled` (primary) + `CursorMoved` (scrolloff can shift w0) → update.
- `WinResized` / `VimResized` → reposition (width) → update.
- `WinLeave` / `BufLeave` / `WinClosed` → close float.
- Call update at the end of `render()` (collapse, live work-tree reload, and
  scope toggle all rebuild rows).
- Guard: cache last `(w0, width, render_gen)` and skip if unchanged
  (`WinScrolled` fires frequently). Bump `render_gen` each `render()`.
- On buffer wipeout/delete cleanup, close and forget the float winid.

Driver is **topline**, not cursor: the context pins to the first *visible* row so
it updates on `<C-e>/<C-y>` even with a stationary cursor. (Confirm this is the
intended semantics with the user; cursor-mode is a trivial swap if not.)

Invariants:
- The float never receives focus or cursor (`focusable=false`, separate buffer),
  so all glean keymaps (`m`, `=`, `c`, `]c`, `]f`, `<CR>`, `u`) are unaffected.
- The float lives in NS-independent buffer/window state; it must not perturb
  `NS`/`NS_INTRA`/`NS_CURSOR` extmarks or the `_line_marks` downgrade logic.
- `ancestry` and `row_hl` are rebuilt on every `render()` and must stay in sync
  with `row_map` (same pass, same row indices).
- A collapsed parent simply shortens the chain — no special-casing needed.
- Combined scope yields at most 3 pinned rows (no commit header); commits scope
  at most 4.

Edge cases:
- `w0 == 0`, mode header, blank rows, comments section → empty chain → no float.
- Marker rows carry `hunk` + `sec` but are not headers; their ancestry correctly
  pins through the hunk header, and the marker row itself is body.
- Buffer shown in two windows → float is per-`self.win`; acceptable.
- Narrow window → `wrap=false` clips rather than wrapping.
- Cursor landing under the float after `]c`/`]f`/`<CR>` near the top — the one
  genuine UX wrinkle. Mitigate with `scrolloff >= #maxpinned` on the glean
  window; not a blocker.

## treesitter-context opt-out

In `plugins.lua`, set treesitter-context's `on_attach = function(buf) return
vim.bo[buf].filetype ~= 'glean' end`. It already no-ops without a parser; this
makes the intent explicit and future-proof.

# Stages

## Stage 1 — Ancestry classification (pure)

**Status: DONE.** `M.compute_ancestry(row_map, n)` added in `nvim/lua/glean/init.lua`
(just above `Session:build`); `Session:render()` now stores `self.ancestry` and
`self.row_hl` (from the `highlights` array) with no change to the visible buffer.
Unit tests added in `init_test.lua` (commits + combined fixtures, including the
marker-row-pins-through-hunk case); full suite green (271 init tests). Note:
section-header detection (`seen`/`unseen`) is ordered *before* the file-header
branch because section headers also carry `file`/`cfile`.

- Goal: a pure `compute_ancestry(row_map, n)` returns, for each row, the
  `{commit_row, file_row, sec_row, hunk_row}` snapshot; `render()` stores
  `self.ancestry` and `self.row_hl` without behavior change to the visible buffer.
- Verification (unit, in `init_test.lua`):
  - Behavior: header rows classified into the correct ancestry level; body rows
    inherit the running ancestry; a shallower header clears deeper levels.
  - Setup: construct a `row_map` fixture covering commits scope (commit→file→
    section→hunk→line, plus a marker row) and combined scope (cfile→hunk→line).
  - Actions: call `compute_ancestry`.
  - Expected: each row maps to the expected ancestry tuple; combined-scope rows
    have no commit level; marker-row ancestry includes its hunk.
- Before moving on: confirm `nvim -l nvim/lua/glean/run_tests.lua`, type checks,
  and linting pass.

## Stage 2 — Pinned-set selection (pure)

**Status: DONE.** `M.compute_pinned(ancestry, w0)` added in
`nvim/lua/glean/init.lua` (just below `compute_ancestry`): returns the ordered
`[commit, file, sec, hunk]` rows from `ancestry[w0]`, filtered to `row < w0`;
empty list (no float) when `ancestry[w0]` is nil or all headers are at/below w0.
Note: the iteration coalesces each missing level to `false` (not nil) so a
missing commit level in combined scope doesn't truncate the `ipairs` walk. Unit
tests added in `init_test.lua` (commits + combined fixtures, covering top-of-
buffer, on-header self-exclusion, marker-row, post-section-change, and
past-EOF); full suite green (280 init tests).

- Goal: a pure function maps `(ancestry, w0)` → ordered pinned row list, applying
  the `row < w0` filter and `[commit, file, sec, hunk]` ordering.
- Verification (unit):
  - Behavior: still-visible headers are excluded; empty chain at top-of-buffer /
    blank rows; correct ordering and max length per scope.
  - Setup: reuse the Stage 1 fixtures' ancestry output.
  - Actions: evaluate the selector at several `w0` values (top, mid-hunk,
    just-below-a-header).
  - Expected: pinned lists match by row index and order; empty where expected.
- Before moving on: confirm tests, type checks, and linting pass.

**Status: DONE.** Sticky-header float implemented in `nvim/lua/glean/init.lua`:
`NS_STICKY` namespace; `Session:update_sticky`, `Session:close_sticky`, and
`Session:_close_sticky_win` (just above `Session:hunk_range`). The float reuses
one scratch buffer (`self._sticky_buf`) and window (`self._sticky_win`),
repositioning via `nvim_win_set_config` on later updates. `render()` bumps
`self._render_gen` and calls `update_sticky` at the end; the guard caches
`(w0, width, gen)` and skips no-op updates. Wired in `setup_keymaps`'s
`glean_cursor_<buf>` augroup: `WinScrolled` + `CursorMoved` update, `WinResized`/
`VimResized` reposition (state reset then update), `WinLeave`/`BufLeave`/
`WinClosed` close. BufWipeout/BufDelete cleanup also calls `close_sticky`.
Integration test added in `init_test.lua` (tall single-hunk fixture, real
window): no float at top, full chain pinned mid-hunk with space-prefixed header
text + matching count, window reuse across updates, close back at top, teardown
on window close. Full suite green (293 init tests; all suites pass).

Decision: driver is topline (`line('w0')`), per the plan's stated semantics, so
the context tracks `<C-e>/<C-y>`. Note: stylua's defaults (tabs) conflict with
the repo's 2-space style across the whole pre-existing file and there is no
`.stylua.toml`, so stylua is not the project's formatter; edits follow the
existing 2-space convention. scrolloff polish is deferred to Stage 4.

## Stage 3 — Float window + events

- Goal: scrolling a real glean buffer shows the pinned headers in a top-anchored
  float that updates on scroll/resize, closes on leave, and survives collapse /
  scope toggle / live reload.
- Verification (integration, in `init_test.lua` if the harness supports a real
  window; otherwise a focused manual checklist documented in the stage):
  - Behavior: float contents equal the expected header rows for a given topline;
    float closes when chain is empty; no duplicate float buffers on re-render.
  - Setup: open a session on a fixture diff with a tall hunk; set window height
    small; scroll so a hunk header leaves the viewport.
  - Actions: set topline, trigger the update path, toggle collapse, toggle scope.
  - Expected: float line text matches the pinned header rows (with the leading
    space), highlight groups applied; float reused (single winid); cleaned up on
    buffer wipeout.
- Before moving on: confirm tests, type checks, and linting pass.

## Stage 4 — treesitter-context opt-out + polish

- Goal: treesitter-context explicitly skips `glean` buffers; glean window sets
  `scrolloff` to avoid cursor occlusion under the float.
- Verification:
  - Behavior: ts-context `on_attach` returns false for glean; cursor stays
    visible after `]c`/`<CR>` near the top.
  - Setup: glean buffer with the new config loaded.
  - Actions: navigate hunks near the viewport top.
  - Expected: no ts-context attachment on glean; cursor not hidden by the float.
- Before moving on: confirm tests, type checks, and linting pass.
