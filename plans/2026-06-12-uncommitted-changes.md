# Objective and Context

> Verbatim request:
>
> "let's write a plan for how to handle uncommitted changes.
>
> So in particular these will be attached to kind of a floating commit, which
> means that we can no longer guarantee that line ranges aren't going to be
> meaningful anymore. We need a different way of addressing this content now and
> I think we should basically do it by a hash of the line content or the content
> of the thing. When we say, 'Hey we've seen lines X through Y of this file that
> has some uncommitted changes,' then we should grab a hash of the content of
> that seen block and then save it in a special ephemeral commit location that
> corresponds to 'here's uncommitted stuff.' I think we can basically
> periodically prune that if it gets too large but we don't need to worry about
> that right now."
>
> Prior context in the thread: the user also wants a convenience for reviewing
> "the stuff that's on the current branch and dirty" without passing base/target.
> Reviewing the committed branch already works via a bare `:Glean` (defaults
> `main...HEAD`). The genuinely new piece is folding in **uncommitted** changes.

## What we're building and why

Today glean reviews `base...target` where both are concrete refs. Every reviewed
unit is addressed as `(commit_sha, path, new-file line range)` — stable because a
commit's post-image blob is immutable, so a line number within it never moves.
The persisted ReviewStore is sharded one JSON file per commit sha.

Uncommitted (working-tree) changes have **no commit sha** and **no stable line
numbers**: edit above a region and every line below shifts; the same content can
move freely. So the `(sha, line range)` addressing scheme breaks for this
content. We introduce a single synthetic **floating commit** that represents
"the working tree on top of HEAD," and address its reviewed units by a **hash of
the seen block's content** instead of by line range. A block stays "seen" as long
as that exact content still exists somewhere in the file; if the content changes
it silently reverts to unseen (never a false positive on real content).

## Key entities (and how they change)

- **Floating commit** — a sentinel commit with a fixed reserved id (e.g.
  `WORKTREE`, distinct from any 40-hex sha). It appears last in the commit list
  (after the real `base..HEAD` commits), and its `files` are the parsed
  `git diff HEAD` (working tree vs HEAD: staged + unstaged). When the review
  target is the working tree, the combined diff's target is the working tree too.
- **Content-hash address** — for the floating commit, the atomic reviewed unit
  is a **block hash**: `sha256` of the joined text of the new-file lines the user
  marked, plus the block's line count `n` and the first line's text `head` (a
  cheap anchor used to skip non-matching positions at render time). Stored as
  `{ head, hash, n }`. A current run
  of `n` consecutive new-file lines is "seen" iff its joined text hashes to a
  stored `hash`. This is position-independent — exactly what we need when line
  ranges are no longer meaningful.
- **ReviewStore (extended)** — real commits keep the existing range schema. The
  floating commit gets a parallel, content-addressed schema in its own shard
  (`glean/WORKTREE.json` — or repo-scoped, see Persistence):
  `{ worktree = true, files = { [path] = {
       seen = { { head, hash, n }, ... },
       comments = { [line_content_hash] = { { text }, ... } } } } }`.
  Comments anchor to a single new-file line's content hash (not a line number).
- **Addressing adapter** — the one new abstraction that lets the existing render/
  mark/seen-overlay code stay mostly untouched: a per-commit notion of how marks
  are addressed. Real commits → range adapter (today's `mark_seen`/`seen_ranges`/
  `range_covered`/`covers` over line numbers). Floating commit → hash adapter
  (the same conceptual operations, but over content blocks/hashes).

## Relevant files

- `nvim/lua/glean/git.lua` — add `merge_base`, a worktree diff
  (`git diff HEAD` for the floating commit's files; `git diff <base>` to the work
  tree for the combined target), and blame-of-working-tree support.
- `nvim/lua/glean/state.lua` — add the content-addressed (hash) storage + helpers
  alongside the existing range helpers; keep them clearly separated.
- `nvim/lua/glean/provenance.lua` — map blame's zero/uncommitted sha onto the
  floating-commit id so combined provenance keeps working.
- `nvim/lua/glean/init.lua` — build the floating commit, route authoring/seen/
  comment/jump through the addressing adapter, and add the convenience command.
- `nvim/lua/glean/*_test.lua` + `run_tests.lua` — new fixtures with a dirty work
  tree; tier-1 hash-address math, tier-2 worktree git, tier-3a render/mark.

# Design

## The floating commit

Reserve a non-sha id `WORKTREE` for the working tree. Two diffs feed it:

- **Commit-by-commit scope**: its `files = diff.parse(git diff HEAD)` — the change
  the working tree introduces on top of HEAD. It renders as one more "commit"
  block at the bottom (summary like `● uncommitted changes`).
- **Combined scope**: when the target is the working tree, the net diff's target
  is the work tree. Run `git diff <base>` (two-dot, base→work tree) where `base`
  is resolved to `merge_base(trunk, HEAD)` so we get "everything on this branch,
  committed and dirty, since it forked from trunk." This shows committed *and*
  uncommitted changes in one buffer.

The real commits in the list keep their existing `C^..C` diffs and range
addressing untouched — only the appended floating commit is special.

### Untracked files

`git diff HEAD` omits untracked files, so they must be added explicitly — but
read-only (never `git add -N`, which mutates the index). List them with
`git ls-files --others --exclude-standard` (honoring `.gitignore`) and synthesize
an **all-addition FileEntry** per file: kind `added`, a single hunk whose
DiffLines are the working file's lines, each an `add` with `new_lnum = 1..N` and
no `old_lnum`. These attach to the floating commit alongside the tracked dirty
edits. Content-hash addressing applies unchanged (every line is a new line), and
jump opens the live file (there is no pre-image / no deletions). Binary or
unreadable files are skipped.

## Content-hash addressing (the core idea)

When the user marks new-file lines as seen in the floating commit (a hunk, a
visual span, or the whole file), we:

1. Collect the **text** of the selected *new* lines (adds + surviving context;
   deletion rows contribute nothing, as today).
2. Split into maximal contiguous runs (a visual selection can straddle gaps).
   For each run, store `{ head, hash = sha256(join(run, "\n")), n = #run }` in
   the floating shard's `seen` set for that path, where `head` is the **exact
   text of the run's first line** (a cheap anchor; see below).

At render time, to decide which of a file's current new-file lines are seen — and
crucially *without* hashing an `n`-line window at every position:

- Build the file's ordered list of new-file line texts, plus an index
  `first_line_text -> { positions }` (a map from each line's text to the indices
  where it occurs).
- For each stored `{ head, hash, n }`, look up only the positions where the
  current line text equals `head`. Those are the only possible run starts; every
  other position is skipped without hashing.
- At each candidate start `i`, do the full hash check *lazily*: bail immediately
  if `i + n - 1` runs past the file end, then hash the `n`-line window
  (`join`, `sha256`) and compare to `hash`. The `head` filter means we hash at
  most once per occurrence of the head line rather than once per file position.
- Wherever a window matches, mark those `n` lines seen.

The `head` anchor turns "slide and hash every block" into "jump to the few
positions whose first line already matches, then hash only those." For the common
case (a head line that's unique or rare in the file) this is effectively O(1)
hashes per stored block; sha256 collisions remain a non-practical concern.
This makes "seen" follow the *content*, not the line number: a seen block that
slides up or down because of edits elsewhere is still recognized; a block whose
content is edited stops matching and shows unseen again (safe — never a false
positive). Identical repeated blocks (e.g. several identical lines) may both be
flagged seen; that is acceptable best-effort behavior for uncommitted scratch
content and is documented, not a correctness bug for committed content.

Comments anchor to a **single new-file line's content hash**
(`sha256(line_text)`); on render we show the comment on every current line whose
text hashes to that key. (Same documented identical-line caveat.)

Use `vim.fn.sha256` (built in) for hashing; no new dependency.

## Keeping the existing code mostly intact: the addressing adapter

The render path, seen-overlay (`compute_combined`), `toggle_seen`,
`mark_visual_range`, and comment code all currently call store methods with
`(sha, path, line-number/range)`. Rather than branch on `WORKTREE` at every call
site, introduce a thin adapter resolved from a sha:

- `range adapter` (real commits): unchanged — delegates to today's
  `mark_seen`/`unmark_seen`/`seen_ranges`/`range_covered`/`covers` and
  line-number comment keys.
- `hash adapter` (floating commit): same conceptual operations but it needs the
  file's new-file **line texts** to translate line numbers ↔ content. The Session
  already has each file's parsed DiffLines, so it can supply the text for a given
  new_lnum. The adapter exposes: "is line L seen?", "mark these line numbers
  seen", "unmark", "is range fully seen?", "add/list comment at line L" — all
  implemented via content hashing internally.

This isolates the line-range-vs-content-hash distinction to one module and lets
the higher-level flows (toggle whole hunk/file, visual span, combined overlay)
work unchanged in terms of "new_lnum sets," with the adapter doing the hashing.

## Combined-scope provenance for the work tree

`compute_combined` attributes each combined new line to an owning commit via
`git blame`. Blame of the working tree attributes uncommitted lines to the
**all-zero sha** (`0000000000000000000000000000000000000000`, "Not Committed
Yet"). In `provenance.parse_blame` (or its caller) map that zero sha to the
`WORKTREE` id. Then the existing overlay logic flows: committed lines route to
real-commit range-seen, uncommitted lines route to the floating commit's hash
adapter. `commit_index` must include the floating commit (last), so "earliest
unseen contributor / seen up to" ordering treats uncommitted work as newest.

The tighter `Xe^..TARGET` re-diff only runs when `Xe` is a real commit; if the
earliest unseen contributor is the floating commit, the target end is the work
tree (`git diff Xe^`) — keep the existing "only re-diff when there's a seen
prefix to elide" guard.

## Jump-to-source

For the floating commit / worktree target, add/context lines live in the actual
working tree file, so jump always opens the **live file** (LSP attaches) — never a
`git show` scratch. Deletion rows still resolve to the pre-image ref
(`HEAD`/base) via `git show`. `ref_is_head` already opens the live file when the
ref is HEAD and the file is readable; treat the `WORKTREE` post-image ref as
"live file" directly.

## Persistence

The floating commit's content is not reproducible from a sha, so its shard is
**repo-scoped, not sha-keyed**: name it by a hash of `repo_root` (e.g.
`glean/wt-<sha256(repo_root)>.json`) so two repos don't collide and a clone
doesn't inherit stale dirty marks. It carries `worktree = true` so load/merge
code can pick the hash schema. Saving rewrites just this one shard, like today.
Pruning (dropping block hashes that no longer match any current content) is
explicitly **out of scope** for now — we note it as a future periodic cleanup.

## Convenience command

Add a no-base/target entry point for "current branch + dirty," e.g.
`:Glean` with a bang or a dedicated `:GleanDirty`:
- `base = merge_base(default_base, "HEAD")` (fork point from trunk),
- `target = WORKTREE`.
Bare committed review (`:Glean` → `main...HEAD`) stays the default and unchanged.

## Invariants

- No false positives on committed content: a real commit's marks remain
  range-addressed and immutable; nothing about the floating commit can mark a
  committed line seen.
- Content-hash seen is monotone with content identity: a block is seen iff its
  exact current text matches a stored hash; editing the content reverts it to
  unseen (safe), reverting the edit restores seen.
- The model stays the single source of truth; the buffer remains a pure
  projection; `row_map` still covers every rendered row.
- Real-commit flows (Stages 1–5 behavior, all existing tests) are unchanged when
  the target is a real ref and no floating commit is present.
- The floating shard is repo-scoped and never sha-keyed, so it can't leak across
  repos/clones; an unmatched block/line hash yields "unreviewed," never a wrong
  mark.
- All git invocations stay read-only and scoped to `repo_root`.

# Stages

## Stage 1 — git plumbing for the work tree

- Goal: produce the floating commit's FileEntries and the combined base→work-tree
  diff, plus `merge_base`, with no UI changes.
- Status: DONE. Added `git.worktree_diff`, `git.diff_to_worktree(base)`,
  `git.merge_base`, and `git.untracked` to `nvim/lua/glean/git.lua`; untracked
  files are synthesized as all-addition FileEntries (kind `"add"` to match the
  diff parser's convention rather than the plan's `"added"`; binary/unreadable
  files skipped via a NUL-byte check). Extended `git_test.lua` to leave a dirty
  work tree (staged + unstaged + untracked) and assert all four helpers. Full
  suite green. Note: repo has no stylua/luacheck config; code follows the
  existing 2-space style.
- Verification:
  - Behavior: `git diff HEAD` parses into FileEntries with correct new-file line
    numbers; `git diff <mergebase>` to the work tree shows committed + uncommitted
    changes; untracked files appear as all-addition FileEntries; `merge_base`
    returns the fork point.
  - Setup: tier-2 `make_repo` fixture extended to leave staged + unstaged edits
    and an untracked file in the work tree.
  - Actions: new `git.worktree_diff`, `git.diff_to_worktree(base)`,
    `git.merge_base`, and `git.untracked` (synthesized all-add FileEntries).
  - Expected: parsed hunks/line-numbers match; merge-base sha matches `git
    merge-base` run directly.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 2 — content-hash addressing in the store

- Goal: the hash schema and the range↔content adapter as pure, tested logic.
- Status: DONE. Added to `nvim/lua/glean/state.lua`: pure helpers `block_of`,
  `line_hash`, `compute_seen_lines` (head-anchored window hashing); worktree
  Store methods `wt_commit`/`wt_file`/`mark_seen_block`/`unmark_seen_block`/
  `seen_blocks`/`wt_add_comment`/`wt_comments_for` (slice carries
  `worktree=true`); and the two addressing adapters `range_adapter` (delegates
  to existing range helpers) and `hash_adapter` (translates new_lnum↔content via
  a supplied `lines[new_lnum]=text` map, splitting marked lnums into contiguous
  runs). Persistence reuses the existing `save_commit`/`load` (shard keyed by the
  passed id, e.g. `WORKTREE`); the repo-scoped shard *name* is deferred to the
  Persistence/Stage 5 wiring — Stage 2 only needs round-trip, verified with id
  `WORKTREE`. Extended `state_test.lua` (34 passing) covering block math + head
  anchor (window seen, head-only not seen, moved block stays seen, edited reverts
  to unseen, past-EOF skipped), the hash adapter (mark/unmark/range_covered/
  comment-by-line-hash, comment follows moved content), and worktree shard
  round-trip with `worktree=true`. Full suite green.
- Verification:
  - Behavior: marking line texts seen stores `{hash,n}` blocks; a current file's
    lines are reported seen iff a window matches; the `head` anchor skips
    non-matching positions so only head-matching windows are hashed; an edited
    block reverts to
    unseen; a block that moved (same text, different position) stays seen;
    comment-by-line-hash round-trips; JSON shard round-trips with `worktree=true`.
  - Setup: tier-1, literal line-text lists and a `tempname()` shard dir.
  - Actions: `state` hash helpers + the hash adapter over literal new_lnum→text
    maps.
  - Expected: seen/unseen membership and comment lookups match; mismatched
    content yields unseen; no false positives.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 3 — render + author marks/comments on the floating commit

- Goal: commit-by-commit scope shows the floating commit; `m`/visual `m`/`c`
  author content-hashed seen/comments through the adapter; persists and reloads.
- Status: DONE. `init.lua`: added `M.WORKTREE` sentinel; `M.open` builds the
  floating commit when `target == WORKTREE` (commit list = `base..HEAD` plus a
  trailing `{ sha = WORKTREE, summary = "uncommitted changes", files }` from
  `git diff HEAD` + synthesized untracked files; combined diff uses
  `diff_to_worktree(base)` so open doesn't crash — combined *overlay* routing is
  Stage 4). Introduced `Session:adapter_for(commit, path)` (range adapter for
  real commits, hash adapter for the floating commit) and `Session:worktree_lines`
  (cached working-tree file lines, the content the hash adapter matches against;
  `new_lnum == file line` for both tracked-dirty and untracked files). Converted
  `file_seen`/`commit_seen` to Session methods and routed render
  (`emit_file_body`), `toggle_seen`, `mark_visual_range`, and comments
  (`comment_anchor`/`add_comment_at`) through the adapter — commit scope only;
  combined scope keeps its existing provenance/range path untouched. Persistence
  reuses `save_commit`/`load` keyed by the `WORKTREE` id (repo-scoped shard
  *name* still deferred to Stage 5/Persistence). Also fixed a latent Stage-2 bug:
  `state.range_adapter.range_covered` called a nonexistent `store:range_covered`
  → now `M.range_covered`. Extended `init_test.lua` (73 passing) with a dirty
  fixture (unstaged edit + untracked file): floating commit renders last with its
  summary and the untracked file; marking the file seen stores a content block,
  renders ✓, and survives reopen; editing the underlying file drops the seen
  flag; a comment anchors by line content and re-renders on reload. Full suite
  green; all glean files load cleanly (no stylua/luacheck config in repo).
- Verification:
  - Behavior: floating commit renders last; marking a hunk/visual span seen makes
    those lines render seen and survives reopen; editing the buffer's underlying
    file content (simulated by changing the fixture work tree) drops the seen
    flag; comments render on matching lines.
  - Setup: tier-3a against a dirty fixture; injected repo-scoped shard dir.
  - Actions: call `toggle_seen`, `mark_visual_range`, `add_comment_at` directly.
  - Expected: buffer state + reloaded shard match the content-hash rules.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 4 — combined overlay with the work tree as target

- Goal: combined scope diffs base→work tree; blame's zero sha maps to the
  floating commit; seen overlay/`seen up to`/tighter re-diff work across mixed
  committed + uncommitted ownership.
- Verification:
  - Behavior: (a) committed regions marked seen still drop out; (b) an uncommitted
    line is owned by the floating commit and is unseen until hash-marked; (c)
    marking a mixed combined hunk seen routes committed lines to range-seen and
    uncommitted lines to hash-seen, after which the hunk drops; (d) a comment on
    an uncommitted line lands in the floating shard by line-hash.
  - Setup: tier-3a fixture with overlapping committed edits plus a dirty edit in
    the same file.
  - Actions: review/comment in combined scope; inspect both real and floating
    shards.
  - Expected: ownership routing + overlay match; no false positives on committed
    lines.
- Before moving on: confirm tests, type checks, and linting all pass.

## Stage 5 — jump-to-source + convenience command

- Goal: jump opens the live working-tree file for floating add/context lines (LSP
  attaches) and the pre-image scratch for deletions; `:GleanDirty` (or `:Glean!`)
  opens `merge_base(trunk,HEAD)`→work tree with no args.
- Verification:
  - Behavior: floating add/context jump → live file + correct line; floating
    deletion jump → `git show HEAD:path` scratch; the convenience command resolves
    base/target correctly.
  - Setup: tier-3a dirty fixture; assert opened path/buffer/line/filetype without
    a window.
  - Actions: call `jump` on floating rows; invoke the command's resolver.
  - Expected: live file for new lines, scratch for deletions, correct refs.
- Before moving on: confirm tests, type checks, and linting all pass.

# Open questions

- Floating shard identity: hash of `repo_root` is simplest. If the user wants
  dirty marks to survive across worktrees of the same repo, key by the common
  git dir instead — defer until asked.
- Should staged-only vs unstaged be distinguished? Plan treats the work tree as
  one floating commit (`git diff HEAD`); splitting staged/unstaged into two
  synthetic commits is a possible later refinement.
- Pruning of stale block hashes is deferred (noted as future periodic cleanup).
