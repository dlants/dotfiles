I want smoething that will allow me to review code in neovim. I want to be able to give it two identifiers and pull up all the changes that are in the second that are not in the first (so a branch and a main that has new changes, shows just the stuff that's in the branch that's not in main).

I want everything to appear in one buffer, with diffs of before/after.

I want each file to be collapsible

I want to be able to mark stuff I've reviewed... at a whole-file level, and also at an individual line level.

I want to be able to hit a keybinding on a line and be taken to that line _in the context of the commit_ that it's from. So if the line is there in my current branch, just open the file (so I can use lsp / type Definitions to navigate the code base, etc...)

---

# Restated objective

Build a native-Lua neovim plugin (`glean`) that renders the diff between two
git refs — showing only what's in the *target* that isn't in the *base* — into a
single scrollable buffer. The buffer groups changes by file, each file is
collapsible, and review progress can be marked at both the file and the line
level and persisted across sessions. A keybinding jumps from any diff line to
that line in the real source (live file when possible, else the file's content
at the relevant ref) so LSP/navigation works.

This follows the conventions of the existing homegrown pickers `needle` and
`shuck` (`nvim/lua/`): a single-file Lua module returning `M`, `M.setup` that
registers a user command and highlight groups, plain neovim buffers/windows
(not floats here — a normal buffer in a window), `vim.system` for git calls,
`vim.uv` timers, and JSON state under `stdpath("data")`.

# Review modes

Two layouts of the same branch, both flat in a single buffer, both backed by one
review store. They differ only in how changes are laid out:

- **Combined**: the net diff `BASE...TARGET`, grouped by file. Review status is
  *computed* by overlaying the per-commit review store onto the net diff (see
  supersession below) — you don't mark combined hunks directly; a mark
  decomposes into per-commit marks.
- **Commit-by-commit**: every change laid out flat, commit 1's files/hunks
  first, then commit 2's right below, etc. Each commit's diff is `C^...C`. This
  is the most granular unit and the natural place marks are *authored*.

**Follow-up is not a third mode** — it's the emergent behaviour of the persisted
`seen` state plus seen-initialized collapsing:
- In combined view, fully-seen hunks drop out (the diff is re-run over the tighter
  unseen commit range), so new/superseding changes are all that's left.
- In commit-by-commit view, seen commits/files start collapsed, so only new
  (unseen) commits are expanded.

Only `seen` (and comments) is persisted; `collapsed` is ephemeral session view-
state initialized from `seen` (see Collapse). Gradually marking work `seen`
across sessions *is* the follow-up review story.

# Key entities

- **Review**: a branch under review, identified by `repo_root .. base ..
  target_branch` (hashed). `target` is resolved to a concrete sha at render
  time; the *branch name* is the stable identity so follow-ups attach.
- **Commit**: one commit `C` on the branch (`BASE..TARGET`, chronological). Has
  sha, summary, and the FileEntries produced by its own diff `C^...C`.
- **FileEntry**: a file changed within some scope (a commit, or the combined) —
  path, change kind, parsed Hunks, and an *ephemeral* `collapsed` view flag
  (session-only, not persisted; see Collapse below).
- **Hunk**: a contiguous diff region with old/new start lines and DiffLines.
  A hunk is purely a *render grouping* — it is **not** the unit of identity or
  reviewed state (it has no stable git identity; its boundaries and line numbers
  shift with context settings and neighboring edits). The atomic addressable unit
  is instead a **new-file line range within a commit** (see Addressing below).
- **DiffLine**: `{ kind = "context"|"add"|"del", text, old_lnum, new_lnum }`. The
  thing we review is the *new* code; deletion lines are context/decoration shown
  to explain what the new code replaced.
- **ReviewStore** (persisted JSON): the *single source of truth* — long-lived,
  keyed by **commit sha** (not by branch), so reviews carry over to any branch
  that contains the commit. On disk it is sharded one JSON file per commit (see
  Persistence); in memory it is the merged map. Shape:
  `{ [commit_sha] = { files = { [path] = {
  seen = { <list of seen new-file line ranges> },
  comments = { [new_lnum] = { text, ... } } } } } }`.
  - `seen`: a set of **new-file line ranges** (`{start, end}`, in the commit's
    post-image of the file) the user has marked reviewed. Stored per `(commit,
    path)`; there is no hunk- or file-level boolean. (`collapsed` is *not* stored
    — it's ephemeral view state.)
  - `comments`: notes keyed by a **new-file line number** in the commit's
    post-image. Each line holds a *list* of comment texts, so a file can carry
    many comments and a single line can carry more than one. (A comment on a
    deleted line anchors to the adjacent surviving new-file line number — see
    Addressing.)
  Every mark adds/updates ranges here:
  - mark a hunk seen → add that hunk's new-file line range to `(C, path).seen`,
  - mark a commit seen → add every changed new-file range of `C`,
  - mark a file seen → add the whole file's changed new-file ranges for every
    commit that touches it.
  A line counts as reviewed when it falls inside some stored seen range; a hunk
  is reviewed when its new-file range is fully covered; a file is fully seen when
  all of its changed new-file ranges are covered.
- **Provenance map**: for the combined view, a mapping from each net-diff line
  to the commit that last wrote it. Built from `git blame` (added/context) plus
  a commit-walk for deletions. Drives the computed combined review status.
- **Render model + row_map**: as before — the buffer is a pure projection of
  whichever scope is active, with `row_map[row]` resolving to file/hunk/line.

# Relevant files (to create)

- `nvim/lua/glean/init.lua` — module: command, orchestration, rendering,
  keymaps, actions.
- `nvim/lua/glean/git.lua` — git plumbing: list commits on the branch
  (`BASE..TARGET`), produce per-commit and combined diffs, run `git blame` and
  `git show`.
- `nvim/lua/glean/diff.lua` — parse unified-diff text into Hunk/DiffLine,
  assigning each DiffLine its new-file line number (the addressing basis).
- `nvim/lua/glean/provenance.lua` — build the per-line provenance map for the
  combined view and derive computed review status.
- `nvim/lua/glean/state.lua` — load/save the persisted ReviewStore JSON.
- Registration wired into `nvim/lua/config/plugins.lua` (or wherever needle is
  configured) with a `:Glean {base} {target}` command and keymaps.

# Design

## Computing the diff (B-not-in-A)

Use the three-dot range: `git diff --no-color BASE...TARGET`. The merge-base
semantics mean we see only changes introduced on TARGET since it diverged from
BASE — exactly "what's in the branch that's not in main." Drive file discovery
with `git diff --name-status BASE...TARGET` and per-file content with
`git diff BASE...TARGET -- <path>` (or parse the single big diff once and split
on `diff --git` headers — preferred, one subprocess). Run git via `vim.system`
with `cwd = repo_root`, discovered like shuck's `discover_search_dir`.

## Single buffer with foldable files

Render into one `nofile` buffer. The model is the source of truth; the buffer is
a projection of it. Rendering walks FileEntries in order, emitting:

- a file header line (with reviewed marker + collapsed chevron),
- if not collapsed: each hunk header and its DiffLines.

As we emit, we push a parallel `row_map[row] = { file=i, hunk=j, line=k }` so any
action can resolve the cursor row to its semantic target. Re-render on any model
change (toggle collapse, mark reviewed) — full re-render is simple and fast
enough for review-sized diffs, matching shuck's render-everything approach.

Folding: rather than neovim folds, model collapse ourselves and just omit the
body when collapsed. This keeps view state and rendering in one place and avoids
fold/extmark desync.

### Collapse is ephemeral session view-state

`collapsed` is **not** persisted (it never touches the ReviewStore) — it lives
only for the current session, per file / hunk / "seen up to" region. It is
*initialized* from seen status when a review opens (seen regions start
collapsed), then evolves independently of `seen`:
- A "seen up to <X>" marker row *is* a collapsed region. Pressing `=` on it
  expands to show the seen diff (the changes up to `X`), rendered as a separate
  block from the un-seen remainder below it.
- The un-seen remainder can itself be collapsed with `=` without marking it
  `seen` — collapsing and reviewing are orthogonal.
So `=` toggles the collapse of whatever region the cursor is on; nothing about it
is written to disk.

## Review marks (commit + new-file line range)

The stored unit is always a `(commit_sha, path, new-file line range)`. Authoring
is trivial in commit-by-commit scope (each diff row maps directly to a new-file
line number in that one commit's post-image). The interesting case is the
**combined view**, where adjacent lines in one combined hunk may have been
authored by several different commits. Per-line ownership resolves every combined
action down to per-commit ranges.

### Per-line ownership (the basis)

Every combined DiffLine has exactly one *owning commit* — the commit that last
wrote that line — and, within that commit's post-image, one owning new-file line
number. We obtain this from `git blame -p` on the combined range: blame gives the
originating commit and the line's source line number *in that commit*. The
provenance map is therefore `combined line -> (commit, new_lnum)`.

### Comments → owned by the line's commit

A comment resolves through provenance to its owning `(commit, path, new_lnum)` and
is stored there. So two comments on adjacent combined lines can land on two
different commits — each comment sticks to the commit that actually introduced its
line. A comment on a deletion row anchors to the adjacent surviving new-file line.

### Seen → record the owning commit's new-file range for every line

Marking a combined hunk `seen` means "I've reviewed this as it stands now." We
take the hunk's new-file lines, group them by owning commit (from blame), and add
each commit's covered new-file range to that `(commit, path).seen` set — not just
the newest commit's. So the elided-prefix marker lands on the newest contributor
and the combined hunk collapses, while the per-commit store stays truthful (you
really did see all those commits' lines).

Marking a **file** `seen` in the combined view does the same across the whole
file: every changed new-file line, grouped by owning commit, is added to that
commit's seen ranges, for every commit that touches the file.

Commit-by-commit marks: **Hunk** adds the hunk's new-file range to `(C, path)`;
**Commit** adds all of `C`'s changed new-file ranges; **File** adds the file's
whole changed new-file range for `C`.

Because the addressable unit is a new-file line range (not a whole hunk), seen
marks are **sub-hunk by default**: a **visual-mode** mark over any span of diff
rows translates each selected row to its `new_lnum` and stores exactly that range
(in commit-by-commit scope, one `(C, path)` range; in combined scope, split by
owning commit). Marking a "whole hunk" is just the convenience case of selecting
all of its rows. Deletion-only rows in the selection contribute no new-file line
(they anchor to the adjacent surviving line) and are simply skipped for the seen
range.

### Filtering out what's been seen

The thing we review is the **new lines** (adds + surviving context in the final
file); deleted lines and context are decoration. So "hide what I've seen" is
fundamentally a statement about new lines. We don't try to surgically re-shade a
single big diff — partially hiding lines inside a hunk fights with context and
hunk grouping. Instead we **narrow the diff's commit range** to just the unseen
work, then filter at the hunk granularity. Two cases:

**Single-commit scope.** We only care about lines seen *within this commit*. Diff
`C^..C`. The stored `(C, path).seen` ranges were authored against this very same
diff (same context), so they line up with hunks. Naive filter: **drop any hunk
whose new-file lines are all inside the seen ranges**; show the rest whole.

**Combined scope.** Here a hunk in `BASE...TARGET` can mix lines from many
commits, and seen state is per owning commit, so hunk boundaries won't line up.
We avoid the mismatch by re-diffing a tighter range:

1. Run the full `BASE...TARGET` diff. For each **new** line, get its owning commit
   (blame) and check whether it's covered by that commit's `(commit, path).seen`
   ranges.
2. Drop the seen new lines. What's left is the set of new lines from commits whose
   work you haven't fully reviewed. Take the **earliest** such contributing commit
   `Xe` (and TARGET as the end).
3. Re-run the diff over just that tighter range: `git diff Xe^..TARGET -- path`.
   This drops all the context and deleted lines that existed only to explain
   already-reviewed lines, leaving a much tighter diff focused on the unseen work.
4. Filter *that* diff at hunk granularity: if **every** new line of a hunk is
   already seen (by its owning commit), hide the whole hunk; if **any** new line
   is unseen, show the whole hunk (context and all). Render a `⟶ seen up to <Xe^>`
   marker for the elided prefix.

A file whose every hunk drops out is fully seen and collapses to a single
file-level "seen up to <newest>" row.

This is deliberately *not* a perfect minimal diff — we accept showing a few
already-seen lines as context inside an otherwise-unseen hunk, in exchange for
diffs that are always self-consistent (real context, real adds/deletes from a
real commit range) rather than a hand-sliced `BASE...TARGET`.

This is exactly the follow-up experience: re-opening shows "seen up to <the commit
you last reviewed>" and only the new work beyond.

## Persistence and storage location

Reviews are long-lived and **keyed by commit sha**, not branch — so a comment or
`seen` flag left on a commit reappears in any branch that later contains that
commit (e.g. after rebase-free fast-forwards or cherry-picks that preserve sha).

shuck stores its per-cwd history under `stdpath("data") .. "/shuck"`
(`~/.local/share/nvim/shuck/`). For consistency, glean stores under
`stdpath("data") .. "/glean"` rather than a bare `~/.glean`. Layout: **one JSON
file per commit**, named by its sha (e.g. `glean/<sha>.json`), each holding that
commit's slice of the ReviewStore — `{ files = { [path] = { seen = { ranges },
comments = { [new_lnum] = { ... } } } } }` (no `collapsed` — that's ephemeral).
Keying files by sha (not repo) is
what lets a commit's
review carry across branches and clones; only the commits actually touched are
read on open, and a toggle/comment edit rewrites just that one commit's file
(debounced). Loading a review reads the files for the commits in `BASE..TARGET`.

Comments are authored via a small prompt (`vim.ui.input` or a scratch input
buffer) bound to a keymap on a DiffLine row, appended to that line's list under
its owning `(commit, path)`'s `comments` map keyed by `new_lnum`, and rendered as
virtual text / extmarks on that exact line (stacking when a line has several).

## Supersession and the combined overlay

The combined diff `BASE...TARGET` is the net of many commits; a later commit can
overwrite lines an earlier commit introduced. We don't store an explicit
supersession graph — we let blame + the tighter re-diff (above) handle it. Blame
on the new lines tells us each surviving line's owning commit; dropping the seen
ones gives the earliest unseen contributor `Xe`, and `git diff Xe^..TARGET`
naturally reflects whatever superseded what.

This gives the behaviour the user wants for free:
- Review a region commit-by-commit; if no later commit touches it, all its new
  lines are seen and its hunk drops out entirely.
- If a later commit *supersedes* part of the region, that commit's new lines are
  unseen, so `Xe` lands at (or before) it and the `Xe^..TARGET` diff shows exactly
  the new change — "what's new since I looked."

Deletions: blame doesn't attribute removed lines. A net deletion of a BASE line
is attributed to the commit-by-commit hunk that performed the deletion (found by
walking commit diffs). Lines added and later deleted within the range never
appear in the combined diff, so they need no provenance.

## Follow-up (an emergent property, not a mode)

When `TARGET` advances, the ReviewStore (keyed by absolute commit shas) is
untouched: already-seen commits stay seen, new commits are unseen. Both views
then naturally isolate the new work:
- **Commit-by-commit**: on open, seen commits/files start collapsed (collapse is
  initialized from seen), so only new/unseen commits are expanded; the user can
  freely re-expand or collapse without changing seen state.
- **Combined**: fully-seen hunks drop out and the diff is re-run over the tighter
  `Xe^..TARGET` range, so new work is all that's left to read; a "seen up to <Xe^>"
  row marks the elided prefix and `=` re-expands the seen part on demand.

Collapse is ephemeral session view-state initialized from seen, then independent
(see Collapse above). No special "what's new" mode is needed — the persisted seen
ranges plus seen-initialized collapsing is the follow-up story.

## Addressing for persistence (the stable part)

A mark's address is `(commit_sha, path, new-file line number/range)`. The key
insight: a commit's post-image blob for a file is **immutable**, so a line number
within that blob is stable forever — unlike a hunk, whose boundaries shift with
context settings and neighboring edits, a `(commit, path, new_lnum)` never moves.
Hunks are only a render grouping; we never persist a hunk identity.

- **Seen** is stored as a set of new-file line *ranges* per `(commit, path)`.
  Marking a hunk/commit/file adds the corresponding new-file ranges. On reopen we
  re-derive each diff row's `new_lnum` and test membership in the stored ranges.
- **Comments** are keyed by a single new-file `new_lnum` per `(commit, path)`.
  Add/context rows use their `new_lnum` directly; a comment on a deletion anchors
  to the adjacent surviving new-file line.

Because `commit_sha` is immutable, an entry is stable forever. If a commit is
rebased/amended its sha changes and its entries simply stop matching — those lines
show unreviewed/uncommented, which is safe (never a false positive, never
misplaced). A stored `new_lnum` past the file's end (shouldn't happen for a fixed
sha) is dropped rather than misrendered.

## Jump-to-source in commit context

On the jump keybinding, resolve the row to its DiffLine and file:

- Determine the target line number: `new_lnum` for context/add lines, `old_lnum`
  for del lines.
- If the relevant ref is the currently checked-out HEAD (compare `target` to
  `git rev-parse HEAD` / branch name) and the file exists in the working tree,
  `:edit` the real file and jump to the line → LSP works.
- Otherwise open a read-only scratch buffer populated from `git show REF:path`
  (REF = target for add/context, base for del), set filetype from the extension
  so syntax works, and jump to the line. LSP won't attach (not a real file) but
  navigation/reading does.

Invariants:
- The model is the single source of truth; the buffer is always a pure
  projection (never edited directly — buffer is non-modifiable except during
  render).
- `row_map` is rebuilt on every render and always covers every rendered row.
- The ReviewStore is the only source of truth; combined review status is always
  computed from it via provenance, never stored separately.
- Persistence never produces false positives: an unmatched `(commit_sha, path,
  new_lnum)` yields "unreviewed," never a wrong mark.
- A line's combined provenance is the latest commit that wrote it; marking
  commit-by-commit and viewing combined must agree for un-superseded regions.
- All git invocations are scoped to `repo_root` and read-only.

# Testing

Tests are headless and dependency-free, run via neovim's bundled LuaJIT
(`nvim -l <file>`), mirroring `nvim/lua/needle/score_test.lua`: sibling-resolved
`package.path`, a tiny `pass/fail` assert harness, exit 0 on success / 1 on any
failure. Extract the shared assert helpers into `nvim/lua/glean/testutil.lua`
and add a single aggregator (`nvim/lua/glean/run_tests.lua` or a `just`/`make`
target) that runs every `glean/*_test.lua` so verifying a stage is one command.

The glean code must be injectable on `repo_root` and the git-runner so tests can
either stub git entirely or point at a throwaway repo — never rely on cwd.

Three tiers (we stop at 3a — no child-process/RPC harness; the actual-keymap /
`feedkeys` flows are verified manually):

- **Tier 1 — pure logic** (`diff.lua`, `state.lua`, range/seen math). Feed canned
  unified-diff *strings* (no git) and assert parsed Hunk/DiffLine structure and
  each line's `new_lnum`; cover adds, deletes, pure-context, multi-hunk,
  no-newline-at-eof, empty file. Test range-coverage / range-merge / earliest-
  unseen-contributor (`Xe`) selection as pure functions over literal range
  tables. Round-trip `state.lua` JSON shards in a `tempname()` dir (shard-by-sha,
  merge-on-load, unmatched `new_lnum` drops cleanly).

- **Tier 2 — git fixtures** (`git.lua`, `provenance.lua`, end-to-end filtering). A
  reusable `make_repo(spec)` helper builds a repo in a `tempname()` dir: `git
  init`, fixed identity, deterministic author/committer dates and `GIT_*` env so
  shas are reproducible; apply a list of `{ path, content }` commits. Run git via
  the same `vim.system(..., { cwd = repo })` path the real code uses. Capture
  shas from `make_repo` at runtime and assert against those (don't hardcode).
  Drive `git.commits`, `commit_diff`, `combined_diff`, blame, and the
  `Xe^..TARGET` re-diff; verify supersession, tighter-range filtering dropping
  seen context, and blame-based ownership. Keep fixtures hermetic:
  `GIT_CONFIG_GLOBAL=/dev/null`, fixed `user.name/email` and dates, temp `HOME`.

- **Tier 3a — in-process headless buffer/UI** (`init.lua`). A `nvim -l` script is
  a full neovim, so build a Tier-2 fixture, call the render/open entrypoint
  against it, and assert on observable buffer state: `nvim_buf_get_lines` text,
  `row_map`, comment extmarks/virt_text, collapse re-render. Drive actions by
  **calling the action functions directly** (`toggle_seen`, `mark_visual_range(s,
  e)`, jump) with cursor/visual range set via `nvim_win_set_cursor` rather than
  feeding keystrokes — deterministic. Covers Stage 2/3/4 buffer behavior and
  Stage 5 jump-to-source (live file when target == HEAD vs. read-only `git show`
  scratch buffer; assert buffer name, line, filetype).

The per-stage Verification blocks below assume this harness; map roughly as Stage
1 → Tier 1 + Tier 2, Stages 2–4 → Tier 3a (with Tier 2 fixtures), Stage 5 → Tier 3a.

# Stages

> **Status: DONE.** Implemented `nvim/lua/glean/diff.lua` (pure unified-diff
> parser producing FileEntries/Hunks/DiffLines with `new_lnum`) and
> `nvim/lua/glean/git.lua` (`git.new{repo_root, run}` injectable handle with
> `commits`, `commit_diff`, `combined_diff`, `range_diff`, `blame`, `show`,
> `rev_parse`, plus `discover_repo_root`). Added the shared `testutil.lua`
> harness (`make_repo` fixture builder + assert helpers), Tier-1 `diff_test.lua`,
> Tier-2 `git_test.lua`, and `run_tests.lua` aggregator (`nvim -l
> nvim/lua/glean/run_tests.lua`). All suites green (56 assertions).
> Decisions/deviations:
> - `git blame` is invoked without `--no-color` (blame rejects it as ambiguous);
>   other diff commands keep `--no-color`.
> - Files match the repo's existing 2-space Lua style (needle/shuck); the repo
>   has no enforced stylua/lua-language-server CLI gate (committed needle code
>   fails both), so the test suite is the verification gate.

## Stage 1 — git + diff parsing

- Goal: list commits on `BASE..TARGET` and, for any `(scope)`, produce ordered
  FileEntries with parsed Hunks/DiffLines carrying correct new-file line numbers.
  No UI.
- Verification:
  - Behavior: a multi-commit fixture yields the right commits, files, hunks, and
    per-line new-file line numbers.
  - Setup: temp git repo (shell): base commit, branch, several commits editing
    overlapping regions.
  - Actions: `git.commits`, `git.commit_diff`, `git.combined_diff`, `diff.parse`.
  - Expected: commit list + per-line kinds/line-numbers match; new-file line
    numbers stable across repeated parses.

> **Status: DONE.** Implemented `nvim/lua/glean/init.lua`: a `Session` model
> (FileEntries from `git:combined_diff(base, target)` with an ephemeral
> `collapsed` flag) projected into one `nofile` buffer via `Session:build`
> (pure: returns lines + `row_map` + highlights) and `Session:render`. Every
> rendered row is covered by `row_map[row] = { file, hunk?, line? }`. `=`
> toggles collapse of the cursor's file (`Session:toggle_collapse`), `q` closes.
> `:Glean [base] [target]` (defaults `main`/`HEAD`) opens in a new tab. Wired
> `require("glean.init").setup()` into `nvim/init.lua` and disabled cmp for the
> `glean` filetype in `config/plugins.lua`. Added Tier-3a `init_test.lua`
> (render text, full row_map coverage, collapse hides body / re-expand
> restores) — all suites green (70 assertions).
> Decisions/deviations:
> - Combined scope only this stage; commit-by-commit / seen / comments are
>   Stage 3+.
> - `open()` takes `open_window=false` and injected `repo_root`/`run` so tests
>   inspect buffer state without a window; the buffer name is suffixed with the
>   buffer id to avoid E95 name clashes across multiple opens.
> - Folding is modeled (body omitted when collapsed), not neovim folds, per the
>   plan, keeping view state + rendering in one place.

## Stage 2 — render a single scope with collapse (combined first)

- Goal: `:Glean base target` renders the combined scope; files collapsible;
  `row_map` resolves cursor to file/hunk/line.
- Verification:
  - Behavior: collapsing a file removes its body, others intact, cursor stable.
  - Setup: open against the Stage 1 fixture.
  - Actions: cursor on header, toggle key.
  - Expected: body hidden, chevron flips, rest unchanged.

## Stage 3 — commit-by-commit scope + seen marks + comments + persistence

- Goal: switch to commit-by-commit scope; toggle `seen` at hunk/commit/file level
  and attach optional comments; all resolve to `(commit_sha, path, new-file line
  range/number)` entries in the ReviewStore under `stdpath("data")/glean`; persists across
  reopen, keyed by commit sha so it survives a branch change. `collapsed` is
  ephemeral (not persisted) and just toggles the view with `=`.
- Verification:
  - Behavior: marking a commit sets `seen` on all its hunks; multiple comments on
    distinct lines (and several on one line) round-trip on the right DiffLines;
    reopening restores `seen` and all comments but **not** any collapse state
    (collapse re-initializes from seen); checking out a different branch that
    contains the same commit still shows its state; an amended commit (new sha)
    loads unseen.
  - Setup: mark seen, collapse/expand some items with `=`, comment; save; reopen.
  - Actions: toggle seen keymap, press `=` to collapse/expand, run the comment
    prompt at hunk/commit/file level; close; `:Glean` again (and on another
    branch).
  - Expected: `seen`/`comment` restored by sha; collapse not persisted; no false
    positives.

## Stage 4 — combined overlay via provenance (supersession + follow-up)

- Goal: combined scope computes seen status via per-line ownership + the tighter
  `Xe^..TARGET` re-diff + hunk-granularity filtering; combined marks/comments
  resolve correctly to per-commit state; superseded regions render unseen;
  advancing TARGET surfaces only new regions.
- Verification:
  - Behavior: (a) a region fully seen commit-by-commit drops out of the combined
    view (its hunks all elided, "seen up to" row shown); (b) a later commit
    overwriting part of it makes `Xe` land at/before it so the `Xe^..TARGET`
    re-diff shows only the new change; (c) marking a mixed-commit combined hunk
    seen adds each new line's range to **every** owning commit's `(commit,
    path).seen`, after which the hunk drops out; (d) marking a file seen in
    combined adds the file's changed new-file ranges to every owning commit, after
    which every hunk drops and the file shows a single "seen up to <newest>" row;
    (e) a line comment in combined view lands on that line's owning commit, and
    two comments on differently-owned lines route to two commits; (f) adding a new
    commit to TARGET re-opens just its portion via the `Xe^..TARGET` re-diff.
  - Setup:
 fixture with overlapping commits across the same region; then a
    follow-up commit touching part of it.
  - Actions: review/comment in combined scope; inspect per-commit store files;
    extend TARGET, re-open.
  - Expected: store writes match the ownership rules; combined filtering
    isolates new changes; no false positives.

## Stage 5 — jump-to-source

- Goal: jump opens the live file when the relevant ref is HEAD, else a read-only
  `git show REF:path` scratch buffer, cursor on the right line.
- Verification:
  - Behavior: HEAD-vs-base jump opens the real file (LSP attaches); historical
    refs open a scratch buffer with correct content/line/filetype.
  - Setup: both ref configurations against the fixture.
  - Actions: cursor on add/del/context lines, press jump.
  - Expected: correct buffer, line, and filetype.
# Open questions

- Default ref arguments: `:Glean` with no args → `main...HEAD`? Pick a sensible
  default and allow a picker (reuse needle) to choose refs later.
