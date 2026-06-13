# Glean: content-addressed comments (with multi-line segments)

## Objective and Context

### User request (verbatim, latest direction)

> ok... so I think for comments on context, I want to go with the github approach
> - let's address those to the WORKTREE, and content-address them. That is, save
> the line, but also the actual content of the context we captured.
>
> Another thing I'd like to do is allow commenting on multi-line segments (using
> visual mode). I think this will help with that too.
>
> So for comments, we will always address the comment to a file, a line, and
> content-address it. We will search the file for the content. If multiple
> instances are found, we will resolve the one closest to the original line.
>
> If the content is not found, we will still show the comment on the original
> line, but mark it "outdated"

### What we are building

Replace glean's per-commit comment addressing entirely with a single,
**content-addressed** comment model. A comment is `{ path, anchor_line,
content[], body }`:

- `path` — the file.
- `anchor_line` — the line it was authored against (target/worktree coordinate),
  used only as a tiebreak and as the fallback render location.
- `content[]` — the captured text of the commented line(s). A single-line comment
  captures one line; a **visual-mode** comment captures the selected run of lines.
- `body` — the comment text.

Resolution at render time: search the **underlying diff model** the display
buffer is built from (the file's flattened sequence of `DiffLine`s — context,
add, and del rows — not the rendered buffer, and not the raw file) for the
`content[]` block. If one or more matches are found, attach the comment to the
match **closest to `anchor`**. If no match is found, render the comment at
`anchor` and mark it **outdated**. Resolving against the diff model (rather than
the literal display buffer) keeps comments stable across changes to *how* we
display things (collapse, seen sections, scope), and makes deletions just work —
a del row carries its text in the model even though it isn't in the target file.

This abandons the `(sha, side, lnum)` per-commit keying from the previous plan in
favor of GitHub's snapshot/re-anchor approach, applied uniformly to add, context,
and deleted lines. Comments become global per `(repo, path, content)` and
independent of which `base..target` review is open. **Seen marks are untouched**
— they keep their existing per-commit range/hash model.

### Key entities (verified against `state.lua`, `init.lua`, `diff.lua`)

- **Store** (`state.lua`): sharded one JSON file per id. There is already a
  content-addressed worktree path: `block_of(lines) -> {head, hash, n}`,
  `line_hash(text)`, `compute_seen_lines(blocks, line_texts)`, and the
  `hash_adapter`. This is the machinery we generalize: it already matches stored
  content blocks against a file's current line texts.
- **Comments today**: range-adapter comments keyed by `new_lnum` per sha; worktree
  comments keyed by single `line_hash`. Both are replaced.
- **DiffLine** (`diff.lua`): `{ kind, text, old_lnum, new_lnum }`. We capture
  `text` for content and `new_lnum` for the anchor (surviving lines); a deletion
  has only `old_lnum` (see open question on deletions).
- **Session:worktree_lines(path)** (`init.lua`): reads the working-tree file's
  current lines, cached. We generalize to "the reviewed (target) version of the
  file": working tree when target is WORKTREE, else `git:show(target, path)`.
- **collect_comments / emit_comment / comment_anchor / add_comment_at /
  delete_comment_* / open_comment_editor** (`init.lua`): the authoring, rendering
  and summary paths to rework.
- **WORKTREE** (`M.WORKTREE`): the synthetic id whose shard already holds
  content-addressed worktree data; comments live here (always loaded, see below).

### Relevant files

- `nvim/lua/glean/state.lua` — store: unified content-addressed comment records +
  a pure block-matching/resolution helper.
- `nvim/lua/glean/init.lua` — authoring (incl. visual mode), inline + summary
  rendering, resolution wiring, undo/redo. Remove the now-obsolete `load_one`
  second pass and the per-commit comment anchoring.
- `nvim/lua/glean/state_test.lua` — Tier-1 store + resolution tests.
- `nvim/lua/glean/init_test.lua` — Tier-3a authoring/render/summary tests.

## Design

### Comment record + storage

Store all comments in a single, always-loaded shard keyed by `M.WORKTREE`
(per the user's "address those to the WORKTREE"). Under it, per path, keep a
flat list of records:

```
comments[path] = {
  { anchor = <line>, content = { "line1", "line2", ... }, text = "<body>" },
  ...
}
```

Because comments no longer live in per-commit shards, the WORKTREE shard must be
loaded for *every* review (committed-range reviews included), not only worktree
reviews. `Store:load` (or a dedicated comments-load) must always pull it.

### Resolution (pure function)

A single pure helper does the re-anchoring, exercised directly by Tier-1 tests.
It operates over the file's flattened diff-line **texts** (the model the display
is built from), with `anchor` an ordinal position into that same sequence:

```
resolve(content[], anchor, diff_texts[]) -> (start_index | nil)
```

- Find every position `i` in `diff_texts` where the `content[]` block matches
  consecutively (`diff_texts[i..i+n-1] == content`).
- If matches exist, return the one with minimal `|i - anchor|` (ties → lower
  index).
- If none, return `nil` (caller renders at the stored `anchor`, marks outdated).

`diff_texts` is the file's `DiffLine` sequence flattened to text, so context,
add, and del rows are all candidates. The caller maps a returned `start_index`
back to the owning `DiffLine` to attach the comment inline.

This generalizes `compute_seen_lines` from "mark seen indices" to "return match
start positions," and reuses `block_of`/head-anchored scanning so we hash at most
once per occurrence of the first line.

### Authoring

- **Single line** (`c` in normal mode): capture `content = { <row text> }`,
  `anchor = row's new_lnum` (or fallback line for deletions).
- **Multi-line** (`c` in visual mode, new): capture the selected rows' texts in
  order as `content[]`, `anchor =` the first captured row's ordinal. This mirrors
  the existing visual `m` (mark-seen) keymap. The selection is **trimmed to a
  single contiguous run of literal diff-line rows**: decoration rows (file/commit
  headers, hunk headers, seen-section headers, inline comment rows, mode/summary
  rows) are excluded, and capture stops at the first gap so `content[]` is always
  a clean consecutive slice of one file's `diff_texts`. A selection covering no
  diff-line rows is a no-op.
- Both open the existing ephemeral comment editor for the body, then append a
  record to `comments[path]` in the WORKTREE shard and save.

### Rendering

- **Inline**: for each displayed file, resolve each of its comments against the
  reviewed file lines. When a comment resolves to a line currently shown as a
  diff row, emit the comment beneath that row (the existing `emit_comment`,
  extended to multi-line content / blocks). Outdated comments anchor to their
  `anchor` line if visible.
- **Summary** (`collect_comments`): becomes a straight read of `comments[path]`
  for each displayed path — no sha walking, no provenance, no `load_one`. Each
  entry shows its resolved location (or `anchor` + "outdated") and body. The
  recently added `load_one` second pass and `Store:load_one` are removed.

### Coordinate basis for `anchor` / `diff_texts`

`diff_texts` = the file's `DiffLine` sequence (from the review model) flattened
to text, in document order. This is the same model the display buffer is
projected from, so it is independent of display state (collapse / seen sections /
scope) and includes deletions.

`anchor` is the ordinal index of the authored row within that flattened sequence,
captured at authoring time. It is only a tiebreak (when `content[]` occurs more
than once) and the fallback render position when `content[]` is gone. Note the
sequence differs between `commits` and `combined` scope; this is acceptable since
`content[]` is the real key and `anchor` only disambiguates.

Invariants:
- The render must distinguish **literal diff-line rows** (a `row_map` target that
  names an actual `DiffLine`) from **decoration rows** (headers, hunk headers,
  seen-section headers, inline comment rows, mode/summary rows). Content capture
  and the `diff_texts` resolution space include only literal diff-line rows.
- A comment's identity is its `(path, content[])`; it re-anchors as the file
  changes and only falls back to `anchor` when the content is gone.
- Multi-line matching is all-or-nothing: the whole block must appear consecutively
  to count as a match; otherwise outdated.
- Closest-to-anchor disambiguation is deterministic (min distance, then lower
  line).
- The comments shard is always loaded regardless of review type; seen-mark shards
  remain per-commit and unchanged.
- Existing stored comments (old per-sha / single-hash format) are not migrated;
  acceptable for a personal tool (note in Stage 1 whether to discard or one-shot
  convert).

## Open questions / edge cases

- **Deletions / mixed selections.** Resolved by searching the diff model: del
  rows carry their text in `diff_texts`, so a deletion comment (and a multi-line
  selection spanning del + context rows) re-anchors to its rows as long as the
  deletion is still present in the diff. It only goes outdated when those rows
  disappear from the diff entirely.
- **Duplicate content far from anchor.** Closest-to-anchor handles the common
  case; no fuzzy matching beyond exact block equality (deliberately simple).
- **`diff_texts` differs by scope.** The flattened sequence (and thus `anchor`)
  isn't identical in `commits` vs `combined` scope. Acceptable: `content[]` is the
  key; `anchor` only breaks ties. A comment authored in one scope still resolves
  by content in the other.

## Stages

## Stage 1 — Unified content-addressed comment store  ✅ DONE

- Goal: the store holds `{ anchor, content[], text }` comment records per path in
  the always-loaded WORKTREE shard, with add/remove/list operations; the old
  per-sha and single-line-hash comment paths are gone.

Implemented in `state.lua`:
- `M.COMMENTS_ID = "WORKTREE"` — the always-loaded comments shard id.
- `Store:read_shard` extracted; `Store:load` now always pulls the comments shard
  even when its id isn't among the review's seen shas.
- New record API: `Store:add_comment_record(path, {anchor, content, text})`,
  `Store:remove_comment_record(path, record)` (matches by anchor/content/text,
  drops exactly one), `Store:comments_for(path)`. Records live in the comments
  shard under a top-level `comments[path]` list.

Deviation / decision: the old per-sha (`add_comment`/`remove_comment`/
`comments_at`) and single-line-hash (`wt_add_comment` etc.) comment paths are
**left in place for now** rather than deleted in Stage 1. They are still wired
through `range_adapter`/`hash_adapter` into `init.lua`'s authoring/render, which
is reworked in Stage 3; removing them here would break `init.lua` and its tests,
violating the "all green" requirement. They will be removed in Stage 3 when
`init.lua` switches to the new record API. New methods were named
`*_comment_record` to avoid colliding with the existing `Store:add_comment`.
Existing stored comments are not migrated (acceptable per plan).
- Verification (Tier-1, `state_test.lua`):
  - Behavior: a single-line and a multi-line comment round-trip through
    save/reload.
    - Setup: store with injected dir.
    - Actions: add `{anchor=3, content={"two"}, ...}` and
      `{anchor=5, content={"a","b"}, ...}`; reload.
    - Expected: both present under `comments[path]`; remove drops exactly one.
  - Behavior: the comments shard loads even when its id is not among the review's
    seen shas.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 2 — Resolution helper

- Goal: a pure `resolve(content, anchor, diff_texts)` returning the closest match
  start index or nil, with multi-line consecutive block matching.
- Verification (Tier-1, `state_test.lua`):
  - Behavior: single occurrence resolves to its index.
  - Behavior: multiple occurrences resolve to the one closest to `anchor` (ties
    pick the lower index).
  - Behavior: multi-line block matches only when consecutive; partial overlap
    does not match.
  - Behavior: a deletion's text (present in `diff_texts`) resolves; absent content
    returns nil (→ outdated).
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 3 — Authoring, rendering, summary in init.lua

- Goal: author single-line (`c`) and visual multi-line (`c` in visual mode)
  comments; render them inline at the resolved position and in the summary with
  an outdated flag; undo/redo; remove `load_one`/pass-2 and per-commit comment
  anchoring.
- Verification (Tier-3a, `init_test.lua`):
  - Behavior: comment on a context line shows in the summary and inline at the
    line (covers the original bug).
  - Behavior: a visual selection over multiple lines stores one comment whose
    content is the selected block and renders once; a selection that also covers
    decoration rows (e.g. a hunk header) is trimmed to the contiguous diff-line
    run, so `content[]` holds only the literal diff lines.
  - Behavior: when the underlying line moves (e.g. reload after the file changes),
    the comment re-anchors to the new position; when the content is gone, it is
    shown outdated at its anchor.
  - Behavior: undo removes a just-added comment; redo restores it.
- Before moving on: confirm tests, type checks, and linting all pass.
