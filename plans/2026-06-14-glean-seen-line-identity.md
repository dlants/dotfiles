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

> **Stage 2 status: DONE.** init.lua gained the canonical resolver:
> `Session:commit_owner`/`combined_owner` (per-line owner closures),
> `line_identity`/`changed_lines`/`line_seen`/`hunk_seen`, and `file_seen`/
> `commit_seen` rewritten to fold over `hunk_seen` (changed lines only, context
> excluded). `emit_file_body` now takes an `owner` and places hunks via
> `self:hunk_seen(...)`; the commit/file header glyphs read the same predicate,
> so placement ⇔ glyph by construction. Add lines resolve in both scopes
> (commit `(sha,new_lnum)`/worktree hash; combined blame owner); commit-scope
> del lines resolve to `(sha,old_lnum)`; combined-scope del lines stay untracked
> (no `new_lnum` → unowned), parity with today, closing in Stage 4.
> Action layer: `apply_seen` now accepts either an identity list (`a.ids`, used
> by commit-scope `toggle_seen`) or legacy `groups` (combined scope +
> visual/marker, untouched this stage). `toggle_seen` commit branch folds the
> target to `target_identities` and marks/unmarks via `store:mark`/`unmark`, so
> commit-scope del lines now participate. `target_seen` reimplemented on
> `hunk_seen`. Decisions/deviations:
> - Pulled the commit-scope mark path onto identities now (rather than fully in
>   Stage 3) because placement ⇔ predicate requires the renderer and the action
>   layer to agree on the same identity set once del lines count. The broader
>   Stage 3 purge (delete `target_seen`/`hunk_anchor_lnums`/`hunk_is_seen`, and
>   migrate visual/marker to identities) remains. `hunk_anchor_lnums`/
>   `hunk_is_seen`/`target_groups` are now dead but left for Stage 3 to remove.
> - `hunk_marker_runs` still keyed off the adapter `resolve` closure (kept
>   alongside the new `owner`); its per-line seen check coincides with the
>   identity predicate for add lines, so markers stay consistent.
> - init_test `stage3 fall-through` shared its store with the prior whole-hunk
>   mark; under the corrected `file_seen` (changed-lines, not full range incl.
>   context) that commit now collapses as fully seen, so the test was given its
>   own fresh store to exercise fall-through from scratch.
> - Added init tests: resolver placement⇔predicate + header-glyph agreement,
>   commit-scope deletion-only hunk participates (seen section + `seen_del`),
>   and per-line committed-vs-dirty identity (committed `B` line-addressed,
>   edited `D` content-addressed). Full suite green (init 221→233, state 64).

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

> **Stage 3 status: DONE.** The action layer is now identity-only in both
> scopes. `target_identities` is scope-aware (commit & combined), folding a
> commit/file/cfile/hunk target to its changed-line identities via
> `changed_lines`. `toggle_seen` is unified: it gathers identities, picks the op
> from `target.sec` (seen→unmark, unseen→mark) or, for headers, from
> `store:all_seen(ids)`, filters to the actually-changing identities, and
> mark/unmarks through `store:mark`/`unmark` — one path for both scopes (the old
> combined `combined_tuples`/`combined_adapter` group path is gone). New helpers:
> `seen_collapse_key(id)` (commit `seen_key`/worktree, combined `cseen_key`) for
> the re-collapse step, and `row_identity(target)` for single-row actions.
> `mark_visual_range` and `unmark_marker` now fold each row to a `line_identity`
> and mark/unmark the identity set directly. `apply_seen` collapsed to a single
> `ids` fold (legacy `groups` branch removed). Deleted: `target_seen`,
> `hunk_anchor_lnums`, `hunk_is_seen`, `target_ranges`, `target_groups`,
> `combined_tuples`, `file_new_ranges`, `hunk_new_range` (all dead once the
> action layer stopped enumerating new-file ranges). `hunk_marker_runs` is kept
> (renderer + marker_test). Decisions/deviations:
> - Header op decision uses `all_seen(ids)` rather than the old per-hunk
>   `hunk_seen` fold (`target_seen`). For a header these agree whenever every
>   hunk has ≥1 changed line; they can differ only for a combined del-only hunk
>   (0 identities today) — an accepted, Stage-4 edge.
> - `present_owners` left in place (pre-existing, untouched by this stage).
> - Added init tests (init 233→240): context lines are never filled when marking
>   a hunk (only the add line's range), mark+unmark is byte-identical JSON, and
>   undo/redo restore the exact identity set. Full suite green (init 240,
>   state 64). No stylua/luacheck gate in the repo; `nvim -l run_tests.lua` is
>   the gate.

## Stage 3 — Action layer consumes identities only

- Goal: rewrite `toggle_seen`, visual `mark_visual_range`, and marker unmark to
  operate purely via `changed_lines` + `line_identity`, grouping identities by
  owning shard and calling the unified adapter. Delete `target_seen`,
  `hunk_anchor_lnums`, `hunk_is_seen`, and the duplicated grouping blocks.
  Section-directed dispatch (`target.sec`) stays. Mark/unmark of a hunk/file/
  commit/visual-selection is defined solely as add/remove over its changed-line
  identities.
- Verification (Tier-3):
  - [x] Behavior: marking a context line inside an already-seen hunk is a no-op
    (context carries no identity) — no "filling", single-press semantics.
  - [x] Behavior: mark then unmark a hunk leaves the store byte-identical (assert
    on encoded shards).
  - [x] Behavior: visual selection marks exactly the changed lines in the span
    (covered by the existing combined/commit marker suites).
  - [x] Behavior: undo/redo of a seen mark restores the exact prior identity set.
- [x] Before moving on: confirm tests, type checks, and linting all pass.

> **Stage 4 status: DONE.** `combined_owner` now resolves del lines: a deletion
> is owned by the commit that first removed it, via the new
> `Session:del_remover(path, text)` — it scans the ordered commit stack's
> `commit_diff` (oldest-first) for the first del line with the same path+text and
> adopts that commit's pre-image `old_lnum`, yielding `(remover_sha, old_lnum)`
> byte-identical to the commit-scope identity (cross-scope stability). A deletion
> with no committed remover returns nil → `line_identity` content-hashes it under
> WORKTREE. Result is cached per path as `text -> {sha,lnum}` (cleared in
> `reload`). Combined-scope del lines now participate in `hunk_seen`/mark/unmark
> identically to commit scope, with no change needed in `line_identity`/
> `changed_lines`/the action layer (they already branched on the owner's
> kind/sha). Decisions/deviations:
> - Uncommitted deletions use the existing `wt_identity(path, text)` content hash
>   (stored in the WORKTREE shard). The plan's "pinned to the branch name" is
>   subsumed by the per-commit WORKTREE shard sharding already in place; no
>   branch field is added to the identity (kept minimal).
> - `del_remover` scans only real commits (skips the floating WORKTREE commit);
>   the worktree fallback is the nil → WORKTREE path, so a committed remover
>   always wins over a worktree match. First match in chronological stack order
>   wins deterministically for duplicate deleted text.
> - Added init tests (init 240→248): cross-scope del seen (mark in commit scope,
>   seen in combined), worktree-only deletion is content-addressed & markable,
>   and deterministic first-remover when the same text is deleted by two commits.
>   Full suite green (init 248, state 64). No stylua/luacheck gate in the repo;
>   `nvim -l run_tests.lua` is the gate.

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

> **Stage 5 status: DONE.** Invariants locked as tests, docs rewritten, and a
> legacy-worktree migration added. `state.lua`: new `M.migrate_shard(decoded)`
> called from `read_shard` discards a worktree file's legacy block-list `seen`
> (array of `{head,hash,n}`) by detecting array-like `seen` (`seen[1] ~= nil`)
> and resetting it to `{}`; the current per-line hash set (string keys) and all
> committed range shards pass through untouched. Module header docs in
> `state.lua` and `init.lua` rewritten to describe the single seen-line-identity
> representation (three kinds; placement ⇔ predicate by construction); the
> `init.lua` scope comment's "Stage 2/Stage 4" forward-references removed.
> Dead code from earlier stages confirmed absent (`recanonicalize`,
> `hunk_anchor_lnums`, `hunk_is_seen`, `target_seen`, block machinery, etc.).
> New tests: `state_test.lua` (+3 → 67) covers the migration (legacy block seen
> discarded, current hash set survives, post-migration mark round-trips on
> reload); `init_test.lua` (+6 → 254) locks the cross-layer invariants —
> placement ⇔ predicate + glyph agreement on the acted unit, no foreign-shard
> writes (a c2 mark touches only c2's shard, never base/c1), and the redundant-
> mark no-op (re-marking already-seen identities is byte-identical JSON and
> yields zero changed identities). Decisions/deviations:
> - The "no-op redundant mark" invariant is asserted at the store/identity level
>   (byte-identical re-mark + zero changed ids) rather than through the UI
>   toggle: `toggle_seen` is section-directed, so pressing `m` on an already-seen
>   unit *unmarks* it (a deliberate toggle), never a silent no-op. The store-
>   level guarantee is the substance the plan's property names.
> - Migration discards (does not translate) legacy worktree block data, per the
>   plan; worktree marks are cheap to recreate.
> - No stylua/luacheck gate in the repo (stylua is on PATH but there is no repo
>   config and its tab default conflicts with the repo's 2-space style); the
>   `nvim -l run_tests.lua` suite remains the gate. Full suite green (init 254,
>   state 67, all suites pass).

## Stage 5 — Cross-layer invariant tests, cleanup, docs, migration

- Goal: lock the invariants in as tests, remove dead code/comments, update the
  module header docs in `init.lua`/`state.lua` to describe the single
  representation, and decide migration for any pre-existing worktree block data
  (simplest: ignore/discard old block shards on load, since worktree marks are
  cheap to recreate; document the choice).
- Verification:
  - [x] Property: placement ⇔ predicate across a generated multi-commit fixture.
  - [x] Property: no shard outside the review's commit set (plus `WORKTREE`) is
    written by any mark.
  - [x] Property: marking an already-seen unit changes nothing (byte-identical
    re-mark + zero changed identities). See note: the UI toggle is section-
    directed, so this is asserted at the store/identity level.
  - [x] Property: round-trip — after a seen action, the acted unit renders in the
    intended section and its header glyph agrees.
- [x] Before moving on: confirm the full suite (`nvim -l nvim/lua/glean/run_tests.lua`),
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
