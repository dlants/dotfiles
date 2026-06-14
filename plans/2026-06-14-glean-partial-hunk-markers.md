# Glean: partial-hunk "seen" markers (collapsible sub-ranges)

## Objective and Context

### User request (verbatim)

> In Glean I'd like to allow the user to partially mark large hunks as seen. The
> way that this would work is that I'd be able to go into visual mode, select a
> part of the hunk like some lines, and then hit M. This should be a new stored
> marker which associates with the hunk and the line range and the content for
> the work tree hunks. It doesn't transition the hunk into a seen state. In the
> unseen state it collapses the lines that were marked and clearly visually
> indicates that they are marked so it collapses them into a single row that
> says, "Hey you've seen this range of like 10 lines or whatever." I can hit the
> = on it to toggle it to expand it and collapse it. When it's expanded it should
> show clearly that this section is marked as seen. I should be able to unmark it
> as seen by, I think, hitting M on that line, the collapse line, or any line
> that is uncollapsed.
>
> selection over a "seen" line range and marking it seen should supercede it (so
> drop the earlier line range and create a new larger line range). WHen we mark
> the whole hunk as seen, we can drop all the line ranges and just transition the
> whole hunk into seen state.

### What we are building

Within an **unseen** hunk, a user can visual-select a sub-range of lines and press
`m` to mark just those lines seen. The marked lines do not move the hunk into the
file's seen-section; instead each maximal contiguous run of seen lines inside the
hunk renders, by default, as a single collapsed **marker row** like
`✓ marked 10 lines`. `=` on that row toggles it open/closed; when open the marked
lines are shown with `GleanSeen` highlight, clearly flagged as seen. Normal-mode
`m` on the collapse row, or on any line of an expanded marker, unmarks that run
(on a non-marker line, `m` keeps its existing whole-hunk toggle behavior).

This is a **rendering + interaction** feature layered on the *existing* seen store
— a "marker" is just a contiguous run of seen new-file lines inside a hunk that is
not yet fully seen. The two semantics the user calls out fall out of the existing
store math:

- **Supersede** ("selection over a seen range … drop the earlier, create a larger
  range"): `state.add`/`state.merge` already coalesce overlapping/adjacent ranges,
  so marking a selection that overlaps an existing marker grows it into one.
- **Whole-hunk transition** ("mark the whole hunk as seen → drop line ranges,
  transition the hunk to seen"): once every anchor line of a hunk is seen,
  `hunk_is_seen` is already true and the existing seen-section renderer moves the
  whole hunk out of the unseen body. No marker rows are drawn for a fully-seen
  hunk.

### Key entities (verified against `init.lua` + `state.lua`)

- **Seen store** (`state.lua`): per `(sha, path)` a set of inclusive new-file line
  ranges (`Store:mark_seen`/`unmark_seen`/`seen_ranges`, merged via `M.merge`),
  or, for the floating `WORKTREE` commit, content-hash *blocks*
  (`mark_seen_block`/`unmark_seen_block`). This already supports partial-hunk seen
  state; no schema change needed.
- **Adapter** (`range_adapter`/`hash_adapter`): `is_seen(lnum)`, `mark(lnums)`,
  `unmark(lnums)`, etc., all keyed by new-file line number. `mark` groups lnums
  into contiguous runs internally. `Session:combined_adapter(sha, path)` picks the
  right adapter for either scope.
- **`hunk_is_seen(hunk, resolve)`** (init.lua ~182): a hunk is seen iff it has ≥1
  anchor line (add lines, else context, else synthetic deletion anchor) and every
  anchor resolves seen. Decides seen-section vs unseen-section membership.
- **`emit_hunk(hunk, hi, target_base, resolve, base_ord, comments_by_ord, sec)`**
  (init.lua ~477): emits a hunk header + one row per diff line. It already
  receives `resolve` (currently unused inside it) — this is where marker
  collapsing is introduced.
- **`emit_file_body`** (~502): partitions a file's hunks into seen/unseen
  sections, each with its own collapse key (`seen_key`/`unseen_key` /
  `cseen_key`/`cunseen_key`).
- **`row_map` target**: `{commit,file,hunk,line}` (commits) or `{cfile,hunk,line}`
  (combined), plus section flags `seen`/`unseen`/`sec`. Marker rows introduce a
  new `marker` field on the target.
- **`self.collapse`**: process-memory content-addressed override map (survives
  reload/reopen, never persisted). Marker collapse state lives here under a new
  key family.
- **`mark_visual_range(srow, erow)`** (~1247): already collects selected diff
  rows' `(sha, path, new_lnum)` (commits: `dl.new_lnum`; combined: via
  provenance) and performs a `seen`/`mark` action over only the not-yet-seen
  lines. This is the basis for `M`'s mark path.
- **`toggle_collapse`** (~927) / **`section_of`** / **`section_action`**: the
  collapse machinery a marker row hooks into.

### Relevant files

- `nvim/lua/glean/init.lua` — all production changes (render, keymaps, toggle,
  unmark).
- `nvim/lua/glean/init_test.lua` — Tier-3 render/behavior tests; add marker
  coverage; a few partial-seen assertions may shift (enumerated in Stage 5).
- `nvim/lua/glean/state.lua` — read-only; the store already supports partial
  ranges/blocks.

## Design

### Marker = contiguous seen run inside an unseen hunk

A "marker" is not a new stored object. It is derived, at render time, from the
seen store: within a hunk that is **not** fully seen, walk the hunk's diff lines
in order and group maximal runs of consecutive lines that (a) have a `new_lnum`
and (b) `resolve(new_lnum)` reports seen. Each such run is one marker. del lines
(no `new_lnum`) and unseen lines break a run.

Rationale for deriving rather than storing: the store is already the source of
truth for seen line ranges, the user's "supersede" and "whole-hunk" rules are
exactly merge/`hunk_is_seen` semantics, and a derived marker can never drift out
of sync with the seen state (e.g. after undo, reload, or an overlapping mark).

### Rendering (`emit_hunk`)

`emit_hunk` changes from "emit every line" to "emit header, then walk lines
grouping seen runs":

- Maintain the current line index while scanning `hunk.lines`.
- A non-seen line (or a line with no `new_lnum`) is emitted exactly as today
  (its add/del/context highlight, comments, intraline pairing).
- A maximal seen run becomes a **marker**. Compute a stable collapse key for it
  (see below). Default collapsed.
  - **Collapsed**: emit a single row `  ✓ marked N lines` (N = run length),
    highlight `GleanSeen`, target = `target_base ∪ {hunk=hi, sec=sec,
    marker={lo, hi_line, lnum_lo, lnum_hi, hash}}` where `lo`/`hi_line` are the
    run's indices into `hunk.lines`, `lnum_lo`/`lnum_hi` its new-file line span
    (used for marking/unmarking), and `hash` the content hash of the run's line
    texts (used for the collapse key — see "Marker collapse key").
  - **Expanded**: emit a marker header row `  ▾ ✓ marked N lines` (same `marker`
    target, so `=`/`m` act on it) followed by each line of the run rendered with
    `GleanSeen` highlight, each carrying `{line=li, marker=…}` so `m` on any of
    them unmarks the whole run.
- Intraline pairing: seen-run lines that are collapsed contribute no del/add rows
  to `intra_work` (they're not in the buffer); expanded ones may, but since they
  render as `GleanSeen` (not `GleanAdd`/`GleanDel`) they are simply excluded from
  intraline pairing — keep the existing pairing limited to non-marker rows.

Because `emit_hunk` already receives `resolve`, both commits and combined scope
get marker collapsing for free.

### Marker collapse key (content-addressed)

Markers need a `self.collapse` key that is stable across renders and defaults to
collapsed. A line-number anchor is **wrong for live/worktree hunks**: the new-file
line numbers shift as the working tree changes between renders/reloads, so a
`lnum`-based key would silently re-collapse (or mis-match) an expanded marker. The
seen store already content-addresses the floating commit (`M.block_of` →
`sha256` of the joined line texts), so the marker collapse key follows the same
principle: key on the **content** of the run.

Define the marker key as a hash of the run's joined new-file line texts (reusing
`state_mod` hashing, e.g. `state_mod.block_of(texts).hash` or
`state_mod.line_hash(table.concat(texts, "\n"))`):

- commits: `mk:<path>\0<contenthash>`
- combined: `cmk:<path>\0<contenthash>` (combined keys are path-only like
  `cseen_key`/`cfile_key`).

Add helpers `marker_key(path, texts)` and `cmarker_key(path, texts)` near the
other key helpers (~89), each hashing `texts` internally.

Properties this gives us:

- **Stable under line-number shifts** (live/worktree): the same marked content
  keeps its key even when the file grows/shrinks above it, so an expanded marker
  stays expanded across re-renders and reloads.
- **Supersede**: when a marker grows, its content changes and so does its key,
  defaulting the larger marker back to collapsed — acceptable, and the same in
  either growth direction (no asymmetry).
- The `marker` field on the row target therefore carries the run's `texts` (or the
  precomputed hash) so `=`/`m` can recompute the key without re-walking the hunk.

### Keymaps — no new key, overload `m`

No new keybinding is introduced. Both modes keep `m`:

- **Visual `m`** (unchanged) → `Session:mark_visual_range(srow, erow)`: select
  part of a hunk and press `m` to mark those lines seen. This satisfies "select
  part of a hunk, mark it" and "supersede" (the store merges overlapping ranges).
  The meaningful new behavior is the marker *rendering*, which applies to any
  partial seen state regardless of how it was created.
- **Normal `m`** (`Session:toggle_seen`) gains a marker branch at the top:
  - If `target.marker` is present (a collapsed marker row, an expanded marker
    header, or an expanded marker line), unmark that marker's full new-file span
    `[lnum_lo, lnum_hi]` and return. Build `seen`/`unmark` groups the same way
    `mark_visual_range` builds mark groups — commits scope routes
    `(commit.sha, path, lnum)` directly; combined scope maps each `lnum` through
    `provenance` to `(owner_sha, orig_lnum)`. Perform a single
    `{kind="seen", op="unmark", groups=…}` action (reuses `apply_seen`/undo) and
    re-render; the run returns to normal unseen rendering.
  - Otherwise fall through to the existing behavior: toggle seen on the whole
    hunk/file/commit target.

  Factor the unmark logic into a small `Session:unmark_marker(target)` helper
  called from `toggle_seen` for clarity, but it is reachable only via `m`.

### `=` on a marker — toggle collapse

In `Session:toggle_collapse(row)`, handle `target.marker` **before** the
`section_of` branch (a marker row also carries `sec`, which would otherwise route
to the whole section). The marker branch builds a `collapse` action toggling the
marker key (default collapsed, i.e. `cur == nil → true`), performs it, and
re-renders — mirroring the seen-section toggle in `collapse_action`. Add a
`target.marker` branch to `collapse_action` (or a small dedicated path) returning
`{kind="collapse", key=marker_key(...), value=not cur}` with no model mirror
(markers have no model field, like the seen-section override).

`c`/`<CR>` on a collapsed marker row: `comment_anchor`/`jump_target` already
require `target.line`, so a collapsed marker row (no `line`) is inert to them.
`m` on a marker row/line is *not* inert — it unmarks the marker (see above).

### Invariants

- **Marker membership is derived, never stored.** A marker exists iff the store
  reports a contiguous run of seen lines inside a not-fully-seen hunk. Undo/redo,
  reload, and reopen automatically reproduce the right markers.
- **Hunk index stability.** Marker collapsing changes only render output within a
  hunk; `row_map` hunk/line indices for non-marker rows keep meaning, and
  `target.hunk` still indexes `file.hunks`/`cf.hunks` so seen/comment/jump on
  ordinary rows are unaffected.
- **Fully-seen hunk shows no markers.** When `hunk_is_seen` is true the hunk is
  rendered by the seen-section path, not `emit_hunk`'s unseen body, so a fully
  marked hunk transitions cleanly and draws zero marker rows.
- **Supersede is merge.** Overlapping marks coalesce in the store; the derived
  marker for the overlapping region is a single grown run.
- **Marker collapse state is process-memory only** (in `self.collapse`), never
  persisted, surviving reload/reopen like all other collapse keys; default
  collapsed.
- **Combined ownership.** A marker run may span multiple owning commits; unmark
  groups lines by `provenance` owner exactly like `mark_visual_range`, so each
  owner's store is updated and saved.

### Alternatives considered

- *A separate "marker" store namespace* (distinct from seen). Rejected: the user's
  own rules ("supersede a seen range", "mark whole hunk → transition to seen")
  define markers in terms of the seen store, and a parallel store would need
  bidirectional bridging to seen — more code, more drift, no benefit.
- *Collapsing markers in the seen-section too.* Out of scope: the seen-section
  already collapses fully-seen hunks; markers are explicitly an *unseen-hunk*
  affordance.

## Stages

### Stage 1 — marker key helpers + derived runs (no render change)

**Status: DONE.** Added `marker_key`/`cmarker_key` (content-hashed via
`state_mod.line_hash`) near the other key helpers, and module-level
`hunk_marker_runs(hunk, resolve)` after `hunk_is_seen`. Helpers exposed through
`M._internal` for unit testing. New suite `nvim/lua/glean/marker_test.lua`
covers run grouping, deletion-break, empty case, and key stability/prefixes.
Full glean suite green (380 assertions). No luacheck on PATH.

- Goal: pure helper that, given a hunk and `resolve`, returns its marker runs
  (`{lo, hi_line, lnum_lo, lnum_hi, n, texts}`), plus `marker_key`/`cmarker_key`
  (content-hashed). No
  behavior change yet.
- Add `marker_key`/`cmarker_key` near the existing key helpers (~89).
- Add a module-level `hunk_marker_runs(hunk, resolve)` near `hunk_is_seen` (~182):
  walk `hunk.lines`, group maximal consecutive lines with `new_lnum` and
  `resolve(new_lnum)` seen; return the run descriptors. Return `{}` when the hunk
  is fully seen (caller already excludes those, but be defensive).
- Verification:
  - Behavior: runs are correctly grouped and bounded.
  - Setup: a hunk fixture with lines seen at indices {2,3,4} and {7} and a
    `resolve` stub backed by a fake adapter.
  - Actions: call `hunk_marker_runs`.
  - Expected: two runs `[2..4]` (n=3) and `[7..7]` (n=1) with correct lnum spans;
    a hunk with all anchors seen yields runs only for the seen lines but is never
    reached in render because `hunk_is_seen` diverts it.
- Before moving on: tests, type checks (n/a for Lua), lint (`luacheck` if present)
  pass; full glean suite green.

### Stage 2 — render markers in `emit_hunk` (commits scope)

**Status: DONE.** `emit_hunk` now takes a `path` arg and walks `hunk.lines`,
emitting `hunk_marker_runs` as marker rows: collapsed (default) → one
`  ✓ marked N lines` row (no `line` field, `GleanSeen`); expanded → a
`  ▾ ✓ marked N lines` header plus each run line rendered `GleanSeen` with
`{line=ri, marker=…}`. Marker target carries `{lo, hi_line, lnum_lo, lnum_hi,
n, texts}`; collapse key is `marker_key`/`cmarker_key` by scope (default
collapsed). Non-marker lines, comments, and intraline pairing unchanged (runs
excluded from del/add pairing). New init_test covers collapsed row, hidden
marked lines, visible unseen lines, hunk staying unseen, marker target span, and
manual-expand showing the lines. Full glean suite green (191 init assertions).
No luacheck on PATH.

- Goal: an unseen hunk with a partial seen run renders the run as a default-
  collapsed `✓ marked N lines` row; expanding (manually flipping the collapse key
  in a test) shows the lines with `GleanSeen`.
- Modify `emit_hunk` to walk lines and emit marker rows for seen runs (collapsed
  → one summary row; expanded → header + `GleanSeen` lines), per Design. Keep
  non-seen lines, comments, and intraline pairing for non-marker rows unchanged.
- Wire only via the commits-scope `resolve` first (combined `resolve` already
  flows through the same `emit_hunk`, but assert combined in Stage 4).
- Verification:
  - Behavior: partial seen run collapses to a marker row by default; unseen lines
    in the same hunk still render normally; the hunk stays in the unseen section.
  - Setup: commits scope, multi-line single hunk, mark lines [2..4] seen via the
    store (isolated `state_dir`).
  - Actions: render; read joined buffer text.
  - Expected: `✓ marked 3 lines` present; the `+`-text of lines 2–4 absent
    (collapsed); other hunk lines present; no file-level `✓ seen (N hunks)` row
    (hunk not fully seen).
- Before moving on: suite green.

### Stage 3 — overload normal `m` (unmark) + `=` toggle + action wiring

**Status: DONE.** Added a `target.marker` branch at the top of `toggle_seen`
(returns `Session:unmark_marker(target)`), a `Session:unmark_marker` helper that
groups the run's `[lo, hi_line]` lines by `(sha, path)` — commits via
`commit.sha`, combined via `provenance` owner — and unmarks only currently-seen
lines via a reversible `{kind="seen", op="unmark"}` action. Added a
`target.marker` branch at the top of `toggle_collapse` (before `section_of`, since
marker rows also carry `sec`) routing through `collapse_action`, and a marker
branch in `collapse_action` keying on `marker_key`/`cmarker_key` (content-hashed,
default collapsed, no model mirror). New init_test Stage 3 block covers mark,
supersede (merge), toggle+reload persistence, unmark via collapsed row and via
expanded line, whole-hunk transition, and fall-through. Full glean suite green
(209 init assertions, +18). No luacheck on PATH.

- Goal: visual `m` marks a sub-range (existing); normal `m` on a marker row/line
  unmarks the whole run, and on a non-marker target toggles the full hunk as
  today; `=` toggles a marker open/closed and persists across reload.
- No new keymaps. Add a `target.marker` branch at the top of
  `Session:toggle_seen` that calls `Session:unmark_marker(target)` and returns;
  otherwise existing toggle behavior runs.
- Add `Session:unmark_marker(target)` (groups lines like `mark_visual_range`, op
  `unmark`).
- Add `target.marker` handling at the top of `toggle_collapse` and a marker branch
  in `collapse_action`.
- Verification:
  - Behavior 1 (mark): visual `m` over part of a hunk creates a marker; store
    records the range; render shows `✓ marked N lines`.
  - Behavior 2 (supersede): visual `m` over a range overlapping an existing marker
    yields a single merged marker (one row, larger N); store has one merged range.
  - Behavior 3 (unmark): `m` on the collapsed marker row removes the seen range;
    render shows the lines normally again. Same for `m` on an expanded marker line.
  - Behavior 4 (toggle): `=` on a marker row expands it (lines visible, `GleanSeen`
    highlight emitted); `=` again collapses; state survives `reload()`.
  - Behavior 5 (whole-hunk transition): visual `m` over the entire hunk's add
    lines makes `hunk_is_seen` true → hunk moves to the file's `✓ seen` section,
    no marker rows drawn.
  - Behavior 6 (fall-through): `m` on a non-marker hunk line still toggles the
    whole hunk seen (existing behavior unchanged).
  - Setup: commits scope, isolated `state_dir`, a multi-line hunk; drive
    `mark_visual_range`/`unmark_marker`/`toggle_collapse` directly with computed
    rows (as existing tests drive visual actions).
  - Expected: as described per behavior.
- Before moving on: suite green.

### Stage 4 — combined scope

- Goal: markers work in combined scope, including multi-owner runs.

**Status: DONE.** Verified the marker machinery already flows through combined
scope unchanged: `emit_hunk` selects `cmarker_key` by scope (init.lua ~535),
`collapse_action` keys markers on `cmarker_key` (~1070), and `unmark_marker`
groups run lines by `provenance` owner (~1429), mirroring `mark_visual_range`.
No production changes were needed. Added a combined-scope test (init_test.lua
~652) with a fixture whose single hunk's add lines are owned by two commits
(mm.txt: A1@c1, A2/A3@c2): marking A1+A2 creates one marker routed to both
owners' stores, A3 stays unseen so the hunk stays unseen, `=` toggles the
marker (cmarker_key), and `m` unmarks both owners. Full glean suite green
(init 221 assertions, +12; all suites pass). No luacheck on PATH.
- Mostly free (shared `emit_hunk`/`resolve`), but verify and fix combined unmark
  grouping (provenance → owner) and `cmarker_key` usage in `toggle_collapse`/
  `collapse_action`.
- Verification:
  - Behavior: in combined scope, marking part of a file's only hunk creates a
    marker (collapsed by default); unmark restores; a run spanning two owning
    commits unmarks both owners' stores.
  - Setup: a fixture whose single hunk has add lines owned by two commits
    (reuse the existing f.txt/x.txt-style fixtures); combined scope.
  - Actions: visual `m` over a sub-range; render; `m` to unmark; reopen.
  - Expected: `✓ marked N lines` row present then gone; the right owner stores are
    updated (assert via `store:seen_ranges`/`seen_blocks`); reopen preserves seen
    state (collapse defaults collapsed).
- Before moving on: suite green.

### Stage 5 — test sweep + docs

**Status: DONE.** Full glean suite re-run green with no changes needed
(diff 35, git 40, init 221, intraline 49, marker 17, provenance 8, state 52 —
all pass). The partial-seen tests the plan flagged as likely casualties never
broke: earlier stages (2–4) introduced their marker assertions alongside the
collapsing behavior, so no pre-existing test asserted raw `+`-line text for a
now-collapsed run. No marker `c`/`<CR>` regressions. Documented the overloaded
`m` (marker unmark vs whole-hunk toggle), visual `m` partial-mark/coalesce, and
`=` marker-collapse in the `init.lua` header comment (~16–22); there is no
standalone glean README/help in-repo, so the module header is the canonical doc
location. No `luacheck` on PATH.

- Goal: confirm no regressions and document the keybinding.
- Re-run `nvim -l nvim/lua/glean/run_tests.lua` (or `init_test.lua`). Any existing
  test that marked a *partial* range seen and asserted the raw `+`-line text is
  now present will break, because that run now collapses to `✓ marked N lines`;
  update those to assert the marker row (or expand-then-assert). Enumerate and fix
  as they surface — the visual-mark and partial-seen tests around init_test.lua
  lines ~260–330 and ~445–520 are the likely candidates.
- Document the overloaded `m` (marker unmark / whole-hunk toggle) in any in-repo
  help/README for glean if present.
- Before moving on: full suite green; lint clean if `luacheck` available.

## Open questions / cosmetic

- Exact marker strings/indent (`  ✓ marked N lines`, expanded header
  `  ▾ ✓ marked N lines`) are cosmetic; tests should match the stable substring
  `marked %d line` rather than exact spacing.
- Singular/plural ("1 line" vs "N lines") — minor; pick `%d line(s)` or a tiny
  pluralize helper.
- Whether to also collapse seen runs of pure context lines (no add lines): yes,
  any seen `new_lnum` run collapses; this is consistent and simplifies the walk.
