# Objective and Context

## The request (verbatim)

> ok. I do want to have a single representation of what has been seen. I don't want to use hunks, as that's a display-layer concern.
>
> So we have a commit-by-commit view, and a combined view. The combined view is the more complicated one.
>
> Within it, we have the current commit, and we have a set of previous commits. We have a diff, where each line has a source commit.
>
> For these, we have stable coordinates. Add lines are anchored in the current commit.
>
> Remove lines are anchored by the commit that added the line, the commit that removed the line, and the line number of the commit the line came from, which is stable because that commit is immutable. I think we can establish which of the current stack of commits first removes each removed line. If it's removed in the uncommitted state, we can pin it to the current branch name.
>
> For the add lines, if the current commit is *done* then those are also stable. If we're working against uncommitted work, we switch to content-addressing rather than strictly line-addressing. So we store the entire content of the line.
>
> So, for every line in the diff, we now have a clear identity marker. We should store these as seen / not seen. Everything should be resolved off of this representation.
>
> is a hunk seen? -> are all changed lines in the hunk seen?
> mark a hunk seen -> mark each changed line in the hunk as seen
> mark a hunk unseen -> mark each changed line in the hunk as unseen
> mark a visual select seen -> mark each changed line in the select as seen
>
> I think everything just falls out of this.

## What we're building and why

Today "seen-ness" is computed in several places from different line-sets: the
renderer places hunks into the seen/unseen section using an *add-line-anchor*
predicate (`hunk_is_seen` over `hunk_anchor_lnums`), while the action layer
marks/unmarks over the *full new-file range* including context, and the
file/commit rollups use yet another (`range_covered`) derivation. Worktree marks
use a separate content-*block* store with a `recanonicalize` coalescing pass.
These independent derivations drift, which is the root cause of the recurring
"two presses to toggle", "context-line filling", and "header glyph disagrees
with section" bugs.

We replace all of this with **one canonical representation: a flat set of seen
line-identities**. Every *changed* diff line (add or del) maps to a stable
identity. Seen-ness of any display unit (hunk, file, commit, visual selection)
is derived by asking, for each changed line it contains, whether that line's
identity is in the seen set. Hunks become a pure display concern; the model
never mentions them.

## Key entities

- **Line identity** — a stable, serializable key for one changed diff line:
  - *Committed add line*: `(sha, lnum)` where `sha` is the commit that
    introduced the line and `lnum` its line number in that commit's immutable
    post-image. (Commit scope: the commit whose diff shows it. Combined scope:
    the blame owner + `orig_lnum` — the same pair, so identities coincide across
    views.)
  - *Uncommitted add line* (owner = `WORKTREE`): the content hash of the line
    text. Worktree lines have no stable number, so we content-address per line.
  - *Committed del line*: `(remover_sha, old_lnum)` — the commit that removed
    the line and the line's number in that commit's pre-image (its parent),
    both immutable. Carries the line text for robustness/disambiguation.
  - *Uncommitted del line* (removed in the work tree): content hash, pinned to
    the current branch name.
- **changed_lines(hunk)** — the add+del lines of a hunk (context excluded). The
  one place "which lines matter" is defined.
- **Seen set / ReviewStore** — `state.lua`, still sharded one JSON file per
  owning commit sha (plus a `WORKTREE` shard), but each shard now stores seen
  identities rather than the dual range/block representation.

## Relevant files

- `nvim/lua/glean/init.lua` — Session: render projection + action layer. Hosts
  the new `line_identity`/`changed_lines`/`is_seen` resolver and routes render
  and actions through it.
- `nvim/lua/glean/state.lua` — the persisted store + addressing adapters. Gains
  the flat seen-identity API; loses `recanonicalize`, content-block coalescing,
  and the range/hash adapter split.
- `nvim/lua/glean/provenance.lua` — blame parsing (`new_lnum -> {sha, orig_lnum}`),
  used to resolve add/context owners in combined scope. Unchanged in shape.
- `nvim/lua/glean/git.lua` — diff/commit accessors. `commit_diff(sha)` is the
  source for discovering which commit removes a given del line in combined scope.
- Tests: `state_test.lua`, `init_test.lua`, `marker_test.lua` (+ the rest) — the
  custom `nvim -l` harness via `run_tests.lua`.

# Design

## The single representation

The store holds a set of seen line-identities. There is exactly one predicate,
`Session:line_seen(identity)`, and exactly one resolver,
`Session:line_identity(file, diff_line)`, which returns the identity for a
changed line (or nil for a context line / a line we cannot yet address). Every
higher-level question is a fold over `changed_lines`:

- `hunk_seen(hunk)` = every changed line in the hunk has a non-nil identity that
  is seen. (A hunk with no changed lines never happens; a deletion-only hunk is
  seen iff its del lines are seen.)
- `mark(unit)` / `unmark(unit)` = add/remove the identities of every changed
  line the unit covers.
- `file_seen` / `commit_seen` = the same fold over all changed lines in the
  file / commit.

The renderer's section placement calls `hunk_seen` directly, so **"renders in
the seen section" and "the action layer thinks it is seen" are the same
computation by construction.** This is the property whose absence caused the bug
cascade.

## Identity resolution per scope

**Per-line committed-vs-dirty decision.** Whether an add line is line-addressed
or content-addressed is decided *per line*, never per file. We blame the work
tree: every line blame attributes to a real commit keeps its stable
`(sha, orig_lnum)` identity, even when the file also contains dirty lines; only
lines blame attributes to the zero/`WORKTREE` sha (genuinely different from the
latest commit) fall back to a content hash. So editing one line in a long file
leaves every other add line's mark stable and line-addressed; only the edited
line becomes content-addressed. The same rule governs del lines: a deletion made
by a real commit is `(remover_sha, old_lnum)`; only a deletion present solely in
the work tree is content-hashed.

Add/context lines already resolve identically in both scopes today (commit scope
authors against `(commit_sha, new_lnum)`; combined scope authors against the
blame owner `(sha, orig_lnum)` — the same physical pair). We keep that and make
it the *only* add-line rule.

Del lines are new to the model:

- **Commit scope** is trivial: a del line in commit `C`'s diff has identity
  `(C, old_lnum)` directly from the parsed diff (`old_lnum` is in `C`'s parent).
- **Combined scope** must discover the remover. The combined diff shows a net
  del line with an `old_lnum` relative to *base*, which is not stable (base is a
  moving merge-base). We resolve it to the immutable `(remover_sha, old_lnum)`
  by scanning the ordered stack of `commit_diff(sha)` results for the first
  commit whose diff contains a del line with the same text on the same path, and
  adopting *that* commit's `old_lnum`. The result is byte-identical to the
  commit-scope identity, so a mark made in one view is seen in the other. If no
  committed commit removes it, the removal is in the work tree → content hash
  pinned to the branch name.

## Storage layout

Keep per-commit sharding (a mark on `C` lives in `C`'s shard and reappears in
any branch containing `C`). Per file within a shard:

- committed add identities → seen line ranges in post-image coords (the existing
  `seen` ranges — unchanged, so existing data keeps working).
- committed del identities → a parallel set of del ranges/line-set in the
  commit's pre-image coords (new; e.g. `seen_del`).
- `WORKTREE` shard → a flat **set of line content hashes** for both adds and
  dels (replacing the `{head,hash,n}` block list). Per-line hashing removes the
  block-coalescing problem entirely: each line is independent, so mark/unmark is
  pure set add/remove with no `recanonicalize`.

Tradeoff: per-line content addressing cannot distinguish two identical worktree
lines (marking one marks both). This is the user's chosen simplification;
note it as an accepted edge case (the old block approach disambiguated by
surrounding content but caused the coalescing bugs).

## What gets deleted

`hunk_anchor_lnums`, `hunk_is_seen`, `target_seen`, `recanonicalize`,
`mark_seen_lines`/`unmark_seen_lines` block machinery, the range-vs-hash adapter
duality (collapsed behind one identity interface), and the bespoke grouping
blocks duplicated across `toggle_seen` / `mark_visual_range` / `unmark_marker`.

## Invariants

- **Placement ⇔ predicate**: for every hunk in a built model, it renders in the
  seen section iff `hunk_seen` is true iff `file_seen`/`commit_seen` agree at
  the rollup. All read the same `changed_lines` + `line_seen`.
- **Mark/unmark identity**: marking then unmarking the same unit returns the
  store to a byte-identical state; marking an already-seen unit is a no-op
  (zero changed identities, zero shard writes).
- **Cross-scope identity stability**: a changed line has the same identity in
  commit scope and combined scope, so marks made in one view are honored in the
  other.
- **No foreign-shard writes**: marking a unit only writes shards for commits
  within the review range (and `WORKTREE`). Because only add+del (never context)
  lines are addressed, and each is owned by an in-range commit or the work tree,
  context lines owned by out-of-range commits are never persisted.
- **Context lines are never "seen"**: they carry no identity and do not affect
  any seen-ness rollup.

# Stages

> **Stage 1 status: DONE.** state.lua now exposes the flat seen-identity API.
> Committed add ranges kept (`mark_seen`/`seen_ranges`); committed del ranges
> added in pre-image coords (`mark_seen_del`/`unmark_seen_del`/`seen_del_ranges`,
> stored in `f.seen_del`). The `WORKTREE` shard's `seen` is now a flat content-
> hash set `{ [line_hash]=true }` (`mark_seen_hashes`/`unmark_seen_hashes`/
> `is_seen_hash`/`seen_hashes`); `block_of`, `compute_seen_lines`,
> `mark_seen_block`, `mark_seen_lines`/`unmark_seen_lines`, `seen_blocks`, and
> `recanonicalize` are deleted. `hash_adapter` reimplemented on the set (same
> line-number interface, so init.lua stays green untouched). New unified
> identity API on `Store`: `add_identity`/`del_identity`/`wt_identity` plus
> `is_seen`/`all_seen`/`mark`/`unmark`. `unmark` prunes emptied file records so
> mark+unmark is byte-identical JSON (the invariant). Decisions/deviations:
> - init.lua's `range_adapter`/`hash_adapter` are kept (now backed by the new
>   storage) rather than removed; the action/render layers migrate to the
>   identity API in Stages 2–3 as planned, so the project stays green now.
> - state_test.lua block-math tests replaced with per-line-set + del-range +
>   identity round-trip tests (state suite 56→64). init_test.lua's two
>   `seen_blocks` probes switched to `seen_hashes`. Full suite green.
> - No stylua/.stylua.toml or luacheck gate in the repo (repo uses 2-space
>   indent; stylua default is tabs); the `nvim -l run_tests.lua` suite is the gate.

## Stage 1 — Flat seen-identity store (state.lua)

- Goal: `state.lua` exposes a single seen-identity API: committed add ranges
  (kept), committed del ranges (new), and a `WORKTREE` per-line content-hash set
  (replacing blocks). One adapter interface answers `is_seen(identity)`,
  `mark(identities)`, `unmark(identities)`, `all_seen(identities)` uniformly for
  committed and worktree owners. `recanonicalize` and the block list are gone.
- Verification (Tier-1, `state_test.lua`):
  - Behavior: marking add lines then unmarking returns identical JSON.
    - Setup: fresh `state.new({dir=tempname})`.
    - Actions: mark a range, unmark the same range, encode the shard.
    - Expected: equals the empty shard.
  - Behavior: worktree per-line content hashing is order/duplicate independent.
    - Setup: a file's current line texts with a repeated line.
    - Actions: mark line indices; query `is_seen` after a simulated line shift.
    - Expected: a line is seen iff its text is in the set; no block coalescing
      artifacts.
  - Behavior: committed del ranges round-trip through save/load.
- [x] Flat seen-identity store landed; full suite green (state 64, init 221).
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 2 — Canonical resolver + renderer reads through it

- Goal: introduce `Session:changed_lines(hunk)`, `Session:line_identity(file,
  line)`, `Session:line_seen(identity)`, and `Session:hunk_seen/file_seen/
  commit_seen` built purely on them. Rewire `emit_file_body` section placement
  and the file/commit header glyphs to call these. Add lines resolve in both
  scopes (commit: `(sha,new_lnum)`/worktree hash; combined: blame owner). Del
  lines: commit scope `(C,old_lnum)`; combined-scope del lines remain untracked
  for now (parity with today) — a deletion-only hunk in combined scope renders
  as it does today; this gap closes in Stage 4.
- Verification (Tier-3, `init_test.lua`):
  - Behavior: a hunk whose every add line is marked (with an unmarked context
    line) renders entirely in the seen section AND the file header shows the
    seen glyph — the two no longer disagree.
  - Behavior: commit-scope del lines participate — marking a deletion-only hunk
    moves it to the seen section.
  - Property test: for the built model, `hunk in seen section` ⇔ `hunk_seen`
    for every hunk.
  - Behavior: in a dirty file with a mix of committed and edited add lines, the
    committed lines resolve to `(sha, orig_lnum)` and only the edited line is
    content-addressed.
    - Setup: a repo with a committed file; reopen against the work tree with one
      line edited.
    - Actions: inspect each add line's identity.
    - Expected: untouched lines carry their owning commit's identity; the edited
      line carries a content hash.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 3 — Action layer consumes identities only

- Goal: rewrite `toggle_seen`, visual `mark_visual_range`, and marker unmark to
  operate purely via `changed_lines` + `line_identity`, grouping identities by
  owning shard and calling the unified adapter. Delete `target_seen`,
  `hunk_anchor_lnums`, `hunk_is_seen`, and the duplicated grouping blocks.
  Section-directed dispatch (`target.sec`) stays. Mark/unmark of a hunk/file/
  commit/visual-selection is defined solely as add/remove over its changed-line
  identities.
- Verification (Tier-3):
  - Behavior: marking a context line inside an already-seen hunk is a no-op
    (context carries no identity) — no "filling", single-press semantics.
  - Behavior: mark then unmark a hunk leaves the store byte-identical (assert on
    encoded shards).
  - Behavior: visual selection marks exactly the changed lines in the span.
  - Behavior: undo/redo of a seen mark restores the exact prior identity set.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 4 — Combined-scope del-line identity

- Goal: resolve combined-scope del lines to `(remover_sha, old_lnum)` by
  scanning the stack's `commit_diff` results for the first matching deletion (by
  path + text), adopting that commit's `old_lnum`; fall back to a
  branch-pinned content hash when the deletion is uncommitted. Combined-scope
  del lines now participate in `hunk_seen`/mark/unmark, identically to commit
  scope.
- Verification (Tier-3):
  - Behavior: a del line marked seen in commit scope shows as seen in combined
    scope (cross-scope identity).
    - Setup: a repo where commit C deletes a line; open both scopes on the same
      store.
    - Actions: mark the del hunk in commit scope; rebuild combined scope.
    - Expected: the combined-scope hunk reports the del line seen.
  - Behavior: a worktree deletion is markable and persists under `WORKTREE`
    pinned to the branch.
  - Edge: a del line whose text also appears as a deletion in two commits picks
    the first remover in stack order, deterministically.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 5 — Cross-layer invariant tests, cleanup, docs, migration

- Goal: lock the invariants in as tests, remove dead code/comments, update the
  module header docs in `init.lua`/`state.lua` to describe the single
  representation, and decide migration for any pre-existing worktree block data
  (simplest: ignore/discard old block shards on load, since worktree marks are
  cheap to recreate; document the choice).
- Verification:
  - Property: placement ⇔ predicate across a generated multi-commit fixture.
  - Property: no shard outside the review's commit set (plus `WORKTREE`) is
    written by any mark.
  - Property: marking an already-seen unit produces zero `save_commit` calls.
  - Property: round-trip — after any seen action, re-`build()` and assert the
    acted unit's section matches the action's intent.
- Before moving on: confirm the full suite (`nvim -l nvim/lua/glean/run_tests.lua`),
  type checks, and linting all pass.

# Risks / open questions

- **Duplicate worktree lines**: per-line content addressing marks all identical
  lines together. Accepted per the request; flagged for the user.
- **Del-remover ambiguity**: identical deleted text removed by multiple commits
  resolves to the first in stack order. Deterministic but may surprise; covered
  by a test.
- **Behavior change to header glyphs**: `file_seen`/`commit_seen` switch from
  full-range to changed-line coverage. This is the intended fix but is a visible
  change; confirm no feature relied on context coverage.
- **Migration**: old `{head,hash,n}` worktree blocks are not read by the new
  store. Plan discards them (marks are easily re-made); confirm acceptable.
- **Performance**: combined-scope del resolution scans commit diffs; cache per
  path alongside the existing provenance cache so it runs once per render.
