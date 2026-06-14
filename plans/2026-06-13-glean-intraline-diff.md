# Objective and Context

The user's request, captured across the conversation:

> for glean, I want even fancier diffing. Like, when a line is mostly the same,
> I want to highlight just the part of the line that's changed, so things are
> easier to scan visually.
>
> I feel like we could do a dynamic programming thing which "aligns" two
> strings, giving higher scores for contiguous runs.
>
> I don't want to reuse the needle approach here since we're doing slightly
> different things. Needle is meant to work on file paths.
>
> So yeah, let's do gating first. A simple pass to find potential candidates
> that we even want to bother highlighting, then do a refined highlighting pass
> on lines that are inherently similar enough.
>
> I think treating things at the token level does simplify things a lot, so
> let's start there. We can split each character into its own token, except for
> alphanumeric runs and underscore.
>
> Since we're doing tokens, and the number of hunks with removed + added lines
> is pretty small, and lines are generally going to be pretty short, I think we
> can just do the same algorithm for scoring and highlighting. So no gating
> pass. Maybe we can just do early termination? So as we're filling out the DP
> matrix, if we're finding that the lowest cost alignment is getting too high,
> we can just give up on highlighting the line.
>
> I think another architectural thing - we should do the basic highlighting
> pass (just the lines) first, and then take on the refined highlighting in a
> separate, asynchronous process, and fill them in as we solve them. So things
> feel snappier.

## What we're building

Intra-line (word-level) diff highlighting for glean's review buffer. Today a
changed line is painted whole-line as `GleanDel`/`GleanAdd`. We want to keep
that as a dim background, and additionally emphasize *just the changed spans*
of a del/add pair that are "mostly the same", so an edit reads at a glance.

The core is a token-level sequence alignment (Needleman-Wunsch with affine gap
penalties, so contiguous changed runs are preferred over scattered ones). The
same alignment serves double duty: its cost is the similarity signal (via early
termination — if the cheapest alignment cost climbs past a threshold while
filling the DP, we abandon the pair and leave it as plain full-line del/add),
and its backtrace yields the changed token spans to highlight. There is no
separate cheap gating pass.

Rendering is two-phase: the existing synchronous `render()` paints full-line
highlights as it does now, then an asynchronous refinement pass computes
intra-line spans and fills them in as each pair is solved, so the buffer feels
snappy on large diffs.

## Key entities

- **token**: a substring of a diff line. Tokenization rule: a maximal run of
  `[A-Za-z0-9_]` is one token; every other byte is its own single-char token.
  Each token carries its byte offset + length within the source line (extmark
  columns are byte offsets).
- **alignment**: matching of the old line's tokens against the new line's
  tokens. Diagonal step = tokens equal (unchanged); gap step = a token present
  on only one side (changed). Affine gaps make a contiguous run of gaps cheap
  to extend so highlights come out blocky.
- **segment**: a merged contiguous byte range `{start_col, end_col}` of changed
  tokens on one side, ready to become an extmark.
- **pair**: a (del line, add line) coupling within a hunk that we attempt to
  align.

## Relevant files

- `nvim/lua/glean/diff.lua` — pure unified-diff parser; produces the `DiffLine`
  list (`kind = add|del|context`, `text`) we tokenize. No change expected.
- `nvim/lua/glean/init.lua` — `Session:build()` emits rows + `highlights`;
  `Session:render()` applies extmarks in namespace `NS`. Pairing collection and
  the async refinement driver live here; `M.setup` defines highlight groups
  (around the `GleanAdd`/`GleanDel` block).
- `nvim/lua/glean/intraline.lua` — NEW pure module: tokenizer, affine-gap
  alignment with early termination, and line pairing. No nvim API.
- `nvim/lua/glean/intraline_test.lua` — NEW unit tests, mirroring the
  `diff_test.lua` / `run_tests.lua` harness.

# Design

## The pure module (`intraline.lua`)

`tokenize(s) -> { {text, col, len}, ... }`
- Single left-to-right scan. Coalesce `[A-Za-z0-9_]` runs; emit every other
  byte as its own token. `col` is the 0-based byte offset into `s` (before the
  marker prefix is prepended — callers add the +1 marker offset).

`align(a, b, opts) -> { a_segs, b_segs } | nil`
- `a`, `b` are raw line strings (the module tokenizes internally).
- Affine-gap DP (Gotoh): three cost matrices over token sequences —
  `M` (last step aligned a token to b token), `Ga` (gap in a / token consumed
  from b), `Gb` (gap in b / token consumed from a). Costs (minimization):
  - aligned equal tokens: `+0`
  - aligned unequal tokens: disallowed as a single diagonal step — model a
    substitution as gap+gap so it is never "free"; equivalently set diagonal
    mismatch cost very high. (Decide during impl; the LCS-style "only equal
    tokens may align diagonally" framing is simplest.)
  - gap open: `GAP_OPEN`, gap extend: `GAP_EXTEND`, with
    `GAP_OPEN > GAP_EXTEND` so runs are rewarded.
- **Early termination**: after filling each anti-diagonal (or row), track the
  minimum cell value across the frontier; if it already exceeds
  `max_cost(a, b)` (a threshold scaled by the longer line's token count), bail
  and return `nil` — the pair is "too different" to bother. This is the
  gating, folded into the same DP.
- Backtrace from the final cell: diagonal-equal steps contribute nothing; gap
  steps mark the consumed token as changed. Merge adjacent changed tokens on
  each side into byte-range segments → `a_segs`, `b_segs`.

`pair_lines(del_texts, add_texts) -> { pairs, dropped } | nil`
- Decides which del couples with which add inside one hunk's del/add run via a
  second, **order-preserving** NW alignment one level up — the same algorithm
  as the token alignment, but cells are whole lines.
- **Hard stop**: if `#del * #add > MAX_CELLS` (~1000), skip the full m*n DP.
  Fall back to either giving up (plain full-line for the whole block) or a cheap
  greedy/positional pairing (still order-preserving: pair del[i] with add[i]
  along the diagonal, run the inner `align` only on those O(min(m,n)) pairs).
  This bounds the number of inner alignments. Default to giving up; greedy is
  the fancier option if the cap turns out to be hit in practice.
- Build the `m*n` similarity matrix by running the inner `align` on every
  (del, add) cell once, **caching each cell's segments** so the chosen pairs
  reuse them (no recompute). Early-terminated (nil) cells get a sentinel
  "too different" cost so the outer DP will never pair them — it gaps them
  instead. This folds gating into the line level too.
- Inner scores are **normalized by line length** before feeding the outer DP,
  so long and short lines compare fairly.
- **The outer pass uses flat (linear) gaps, not affine** — a single DP matrix.
  Contiguity of matched lines is irrelevant here; the only goal is to maximize
  the *total* similarity of matched pairs. Each diagonal step adds the cell's
  normalized similarity; each gap step subtracts one constant. That gap
  constant is effectively the **similarity threshold** (the single knob on this
  pass): a pair is matched only when its similarity beats the cost of leaving
  both lines unpaired, which also subsumes the early-terminated sentinel.
- Order is preserved by construction (monotonic backtrace; pairings never
  cross). A diagonal step = a paired del/add (carries its cached segments); a
  gap = an unpaired del or add (plain full-line).

## Per-hunk signal-to-noise gate

The emphasis layer is **all-or-nothing per hunk**. The first decision is whether
to show the emphasis layer for the hunk *at all* — the feature exists to surface
a *small* change buried in a *large* hunk, and should get out of the way when the
change is a genuine rewrite.

Within an emphasis-active hunk, emphasis establishes a reading convention:
**emphasized = changed, look here; un-emphasized = unchanged, skip.** An
unmatched add/del line is 100% changed, so leaving it un-emphasized (relying only
on the dim phase-1 `GleanAdd`/`GleanDel` background) is *wrong* — it would read as
"skip me." So unmatched lines must get a **whole-line emphasis span** (the entire
line as one segment), in the same visual vocabulary as the matched pairs' partial
spans. This makes "has emphasis ⇔ changed" hold for every line in an annotated
hunk — no ambiguous middle state where a fully-new line looks ignorable.

Per-line rule inside an emphasis-active hunk:
- matched pair → emphasis on just the changed token spans
- unmatched add/del → emphasis on the entire line
- context / unchanged tokens in matched pairs → no emphasis ("skip")

Emphasis earns its keep by how much it lets the reader *skip*. After the
two-pass alignment (we already have all the data), compute a token-weighted
ratio over the hunk's add/del region (context lines excluded — already visually
distinct):
- **region** = all tokens on the hunk's add + del lines.
- **emphasized** = changed token spans inside matched pairs + the whole-line
  spans of unmatched add/del lines.
- **skippable** = region − emphasized = the unchanged tokens inside matched
  pairs (the only thing left un-emphasized in the +/- region).
- **Suppress when `skippable / region < HUNK_GATE`** → phase-1 full-line only,
  nudging the reader to take in the block as a whole. Otherwise emit emphasis.

`HUNK_GATE` is the single knob (0.75 to start: at least 75% of the changed
region should be skippable for emphasis to be worth it). Whole-line emphasis on
unmatched lines correctly counts as noise, so a hunk dominated by unmatched lines
or heavily-rewritten pairs lands near ratio 0 → suppressed.

This is token-weighted (not line-counted) so a long mostly-unchanged line and a
flurry of short rewritten lines are weighed by real content. It is a second,
coarser knob layered on the per-pair similarity threshold: per-pair decides
*which lines pair*; the hunk gate decides *whether the hunk is clean enough to
annotate at all*. (A v2 could make this graded rather than binary; start
binary.)

## Wiring into the renderer

Phase 1 (synchronous, unchanged behavior): `render()` paints full-line
`GleanAdd`/`GleanDel`/`GleanContext` exactly as today.

Phase 2 (asynchronous refinement):
- During `build()`/`emit_hunk`, additionally record, for each hunk, the buffer
  rows + source texts of its del lines and add lines, so a post-render pass has
  everything it needs: a flat work-list of pairs `{del_row, add_row,
  del_text, add_text}` (rows are needed to place extmarks; pairing via
  `pair_lines`).
- After `render()` applies phase 1, kick off the refinement driver. It walks
  the work-list in chunks (via `vim.schedule` / a short `vim.uv` timer),
  calling `align` on each pair and, for non-nil results, placing
  emphasis extmarks: for each segment, `nvim_buf_set_extmark(buf, NS_INTRA,
  row, marker_off + seg.start_col, { end_col = marker_off + seg.end_col,
  hl_group = ..., priority = <above the full-line hl> })`.
- `marker_off = 1` (the `+`/`-` byte prepended in `emit`).
- New highlight groups `GleanDelEmph` / `GleanAddEmph`, defaulting to link
  `DiffText` (vim's built-in "changed part of a changed line" group), defined
  alongside the others in `M.setup`.

## Namespaces and cancellation

- Emphasis extmarks live in a dedicated namespace `NS_INTRA`, separate from
  `NS`, so phase-2 results are not clobbered by phase-1's
  `nvim_buf_clear_namespace(NS, ...)` and vice-versa.
- A monotonically increasing `self._intra_gen` is captured when refinement
  starts. Every render bumps the generation, clears `NS_INTRA`, and any
  in-flight chunked job checks `gen == self._intra_gen` before scheduling its
  next chunk or writing extmarks — so a reload/re-render mid-flight cleanly
  abandons stale work. Also guard on `nvim_buf_is_valid`.

Invariants:
- Emphasis spans are strictly within their line's byte length (offset by the
  marker); never split a multibyte sequence — because tokens are whole bytes
  for non-word chars and whole `[A-Za-z0-9_]` (ASCII) runs otherwise, segment
  boundaries always fall on byte boundaries that are also char boundaries.
- Phase 1 alone is always a complete, correct render; phase 2 is purely
  additive emphasis. If refinement never runs (or is cancelled), the buffer is
  still correct, just less fancy.
- `align` is total: it returns `nil` rather than throwing on dissimilar or
  empty input; empty line vs non-empty yields a single full-line segment (or
  `nil` — decide, but be consistent).
- Pure module touches no nvim API, so it is unit-testable headless like
  `diff.lua`.

# Stages

## Stage 1 — Tokenizer

**Status: DONE.** Added `nvim/lua/glean/intraline.lua` with `M.tokenize(s)`
(byte-scan coalescing `[A-Za-z0-9_]` runs, every other byte its own token; each
token `{text, col(0-based byte), len}`). New `intraline_test.lua` (12 asserts)
covers coalescing, offsets, empty input, alnum runs, and consecutive
punctuation. Full `run_tests.lua` suite green. Note: repo has no enforced stylua
config (existing `diff.lua` also differs from stylua defaults), so files follow
the repo's 2-space convention.

- Goal: `intraline.tokenize` splits lines into the agreed token model with
  correct byte offsets.
- Verification (unit, new `intraline_test.lua`):
  - Behavior: word/underscore runs coalesce; punctuation/space are single
    tokens; offsets are correct.
  - Setup: literal strings, e.g. `foo_bar(x) = 1`.
  - Actions: call `tokenize`.
  - Expected: token texts `{"foo_bar","(","x",")"," ","="," ","1"}` with
    `col`/`len` matching their position in the source.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 2 — Affine-gap alignment with early termination

**Status: DONE.** Added `M.align(a, b)` to `intraline.lua`: Gotoh affine-gap DP
over token sequences with three cost matrices (`Mm`/`Ga`/`Gb`). Only equal tokens
align on the diagonal (LCS-style); substitutions are modeled as gap-in-b +
gap-in-a, so gap states can transition into each other (the open term of each gap
matrix includes the other gap matrix). Constants: `GAP_OPEN=3`, `GAP_EXTEND=1`,
threshold `max(m,n)*COST_FACTOR` with `COST_FACTOR=2`. Early termination bails to
`nil` when a row's frontier minimum exceeds the threshold; a final cost over
threshold (or `INF`) also returns `nil`. Backtrace collects changed token indices
per side, merged into byte-range `{start_col, end_col}` segments (end exclusive).
Identical lines return empty segment lists (chosen convention). 4 new test blocks
(10 asserts): substitution, contiguous insertion, dissimilar→nil, identical→empty.
Full suite green (330 asserts across 6 suites).

- Goal: `align(a, b)` returns merged changed segments for similar lines and
  `nil` for dissimilar ones; contiguous runs are preferred.
- Verification (unit):
  - Behavior: a one-token substitution highlights only that token on each side.
    - Setup: `a = "value = 1"`, `b = "value = 2"`.
    - Expected: `a_segs` covers just `1`, `b_segs` just `2`.
  - Behavior: an inserted word run produces one contiguous segment, not
    scattered char marks.
    - Setup: `a = "f(x)"`, `b = "f(x, y)"`.
    - Expected: a single `b_seg` spanning `, y`.
  - Behavior: completely different lines early-terminate.
    - Setup: `a = "import os"`, `b = "return None"`.
    - Expected: `align` returns `nil`.
  - Behavior: identical lines yield empty segments (or nil — match the chosen
    convention).
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 3 — Line pairing

- Goal: `pair_lines` couples del/add lines within a hunk run (positional).
- Verification (unit):
  - Behavior: equal-length runs pair index-for-index; unequal runs leave the
    surplus unpaired.
  - Setup: del/add text lists of equal and of differing lengths.
  - Expected: correct `{di, ai}` pairs; no pair references a missing index.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 4 — Synchronous wiring (prove it visually first)

- Goal: emphasis extmarks render correctly when computed *synchronously* at the
  end of `render()` (simplest path; async added next). Build the per-hunk pair
  work-list, define `GleanDelEmph`/`GleanAddEmph`, place `NS_INTRA` extmarks
  with the marker offset.
- Verification: mostly manual/visual on a real `:Glean` diff, plus any pure
  helper that builds the work-list from a hunk can be unit-tested (rows + texts
  collected correctly). Confirm full-line highlights are unchanged and emphasis
  sits on top.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 5 — Asynchronous refinement + cancellation

- Goal: move phase-2 off the synchronous path into a chunked, cancellable
  driver keyed by `self._intra_gen`; re-render/reload mid-flight abandons stale
  work and clears `NS_INTRA`.
- Verification:
  - Behavior: a re-render bumps the generation so a stale in-flight chunk does
    not write extmarks. Where feasible, extract the generation/guard check into
    a tiny testable predicate; otherwise verify by manual reload-spam on a large
    diff plus an assertion that `NS_INTRA` is cleared on each render.
  - Behavior: closing the buffer mid-refinement does not error (guard on
    `nvim_buf_is_valid`).
- Before moving on: confirm tests, type checks, and linting all pass.
