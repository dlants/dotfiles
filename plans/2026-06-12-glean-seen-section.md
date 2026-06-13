# Glean: collapsible per-file "seen" section

## Objective and Context

### User request (verbatim)

> I'm adding a feature to glean.nvim (a code-review buffer). Currently when a user marks a hunk/line as "seen", in COMBINED scope the seen hunks just disappear from view (compute_combined drops them / collapses a fully-seen file to a single line). The user wants instead a collapsible "seen" section PER FILE: when collapsed it's a single line like '▸ ✓ seen (N hunks)'; when expanded it shows the seen hunks. This should apply in both 'commits' scope and 'combined' scope.
>
> Definition of a hunk being 'seen': it has >=1 new line and ALL its new lines are seen by their owner.
>
> [combined algorithm, per user]: for each raw hunk, check each new line's owning commit seen status; if all seen -> seen section.

### What we are building

In both scopes, within each rendered (expanded) file, partition the file's hunks
into **unseen** and **seen** sets. Render unseen hunks in the main body as today.
Collect the seen hunks under a single collapsible **seen-section** header row that
reads `▸ ✓ seen (N hunks)` (collapsed) or `▾ ✓ seen (N hunks)` (expanded). The
seen section defaults to collapsed. This replaces the current combined-scope
behavior where seen hunks vanish (tighter re-diff) and fully-seen files collapse
to a one-line `✓ path ⟶ seen up to SHA` row.

### Key entities (verified against `nvim/lua/glean/init.lua` + `state.lua`)

- **Adapter** (`state.range_adapter` / `state.hash_adapter`): shared interface
  `is_seen(lnum)`, `mark(lnums)`, `unmark(lnums)`, `range_covered(s,e)`,
  `add_comment(lnum,text)`, `comments_at(lnum)`. In commits scope the seen key
  is the file's `new_lnum`; in combined scope ownership is per-line via blame
  provenance, so the key is the owner's `orig_lnum` through that owner's adapter.
- **Provenance** (`Session:provenance(path)`): `new_lnum -> {sha, orig_lnum}`
  (zero-sha remapped to `WORKTREE`). Already cached, keyed by target line.
- **Hunk / diff line**: `hunk.header`, `hunk.lines[]`; each `dl` has `kind`
  (add/del/context), `new_lnum`, `old_lnum`, `text`. `new_lnum` is the target-file
  line for BOTH raw `base..target` hunks and provenance keys (verified: net diff's
  new side == target == blame ref).
- **collapse table** (`self.collapse`): content-addressed override map kept in
  process memory via `views[key]`, so it survives both `reload()` and reopen and
  is never persisted to disk. Existing key helpers: `commit_key`, `file_key`,
  `cfile_key` (lines 84-86).
- **row_map**: `row -> target`. Targets carry `{commit,file,hunk,line}` (commits)
  or `{cfile,hunk,line}` (combined). `hunk` indexes the file's displayed hunk list;
  `line` indexes `hunk.lines`. Actions (toggle_seen, comment, jump, visual-mark)
  all resolve through these indices.

### Relevant files

- `nvim/lua/glean/init.lua` — all changes live here.
- `nvim/lua/glean/init_test.lua` — Tier 3a render/behavior tests; several
  fully-seen / "seen up to" assertions change (enumerated below).
- `nvim/lua/glean/state.lua` — adapter interface (read-only; no changes).
- `nvim/lua/glean/git.lua` — `range_diff` becomes unused by init.lua but keep it
  (it has its own test in `git_test.lua`); no changes.

## Design

### Core algorithm

For each expanded file (in either scope), with a per-line resolver
`resolve(new_lnum) -> (adapter, key_lnum)` (nil for a line with no owner):

1. A hunk is **seen** iff every one of its **anchor lines** resolves to an
   adapter that reports it seen, and there is at least one anchor line. The
   anchor lines of a hunk are:
   - its new-file lines (`new_lnum` of context + add lines), when it has any; OR
   - for a **pure-deletion hunk** (`new_count == 0` — no context, no adds, e.g.
     a whole-file or contextless boundary deletion), a single **synthetic
     anchor** = `max(hunk.new_start, 1)`, the new-file line just after the
     removed region. This lets a deletion be marked/seen by linking it to the
     surrounding new-file content, per the user's request.
   A line whose `resolve` returns nil makes the hunk unseen. Note that a
   deletion hunk that carries context lines is already handled by the first
   bullet — its deletions implicitly follow the seen-ness of its context.
2. Render unseen hunks (including pure-deletion hunks) in the main body, exactly
   as today, preserving each hunk's original index.
3. If any seen hunks exist, emit a seen-section header row; when its (default-on)
   collapse is off, render the seen hunks below it, again preserving original
   indices and GleanSeen highlighting.

The two scopes differ ONLY in the `resolve` closure and the file-header line:
- commits: `resolve = function(ln) return adapter, ln end`, where
  `adapter = self:adapter_for(commit, path)`.
- combined: `resolve = function(ln) local p = prov[ln]; if not p then return nil end;
  return self:combined_adapter(p.sha, path), p.orig_lnum end`.

This unifies the body renderer and guarantees the two scopes behave identically.

### Why drop the combined tighter re-diff (compute_combined)

The current combined view, for a partially-seen file, runs a tighter
`Xe^..target` re-diff and shows only its unseen hunks, plus a `⟶ seen up to SHA^`
marker; a fully-seen file collapses to one `✓ path ⟶ seen up to SHA` line. The
seen content is **gone** from the re-diff output — it cannot be re-expanded.
Showing seen hunks in a collapsible section therefore *requires* working from the
raw `base..target` hunks (`self.files` / `cf.raw.hunks`), which the user's stated
algorithm also assumes. So `compute_combined` collapses to a thin pass that just
applies the file-collapse override and exposes `{path,kind,hunks=raw.hunks,raw}`;
`tighter_diff`, `commit_index`, `fully_seen`, and `seen_up_to` are removed.

Alternative considered: keep the re-diff for the unseen body and ALSO keep raw
hunks for the seen section. Rejected — two parallel hunk decompositions with
mismatched indices would break `row_map`-based actions and roughly double the
code; the user explicitly asked for the raw-hunk algorithm.

### Deletion-hunk seen handling

Pure-deletion hunks (`new_count == 0`: whole-file or contextless deletions) carry
no new-file line to key on, so they need a synthetic anchor to be markable. The
anchor is **owned by the commit that performed the deletion**, not by a surviving
neighbor — so the seen state attaches to the delete, exactly like any other change.

Deletion hunks that carry context (the common case under default 3-line context)
need none of this: they already have context `new_lnum`s and follow them.

- **The anchor commit + line**: the deleting commit's own diff (already in memory
  as `commit.files`, loaded by `build_model` for both scopes) contains this
  deletion as a hunk; its anchor is the **line-after-delete in that commit's new
  file** = `max(thatHunk.new_start, 1)`. For a whole-file deletion the new side is
  empty, so the synthetic line is `1` for that path in that commit.
- **Commit scope** is trivial: the hunk already belongs to a known commit, so
  `hunk_new_range` returning `{max(new_start,1), max(new_start,1)}` for
  `new_count == 0` (see Stage 1) routes through that commit's adapter directly.
  No attribution work.
- **Combined scope** must attribute the net `base..target` deletion hunk to its
  deleting commit. The net hunk's old-line span is in `base` coordinates, while
  each `commit.files` hunk's `old_lnum` is in that commit's *parent* coordinates,
  so a coordinate match is not direct. Use a **reverse-blame provenance** for the
  path — `git blame --reverse <base>..<target> -- path` over the base file — to
  map each deleted base line to the commit in which it was removed; cache it
  alongside `Session:provenance` (keyed by target, like the forward map). Then a
  deletion hunk resolves to `(deleting_commit, line-after-delete-in-that-commit)`,
  and marking routes through that commit's range/hash adapter.
  - Implementation note: add `Git:blame_reverse(base, target, path)` mirroring the
    existing `git blame -p` parser; verify the exact `--reverse` boundary
    semantics (which endpoint's commit is reported) against a 2-commit fixture
    during Stage 3. Cross-check with the in-memory `commit.files` deletions as a
    fallback if reverse-blame proves ambiguous for duplicate lines.
- **`combined_tuples` (line 318)** gains a deletion fallback: when a hunk/file
  target yields no new-line tuples, emit one tuple
  `{ sha = deleting_commit, path, range = {anchorLine, anchorLine} }` from the
  reverse-blame attribution instead of the forward `provenance`.
- **Ripple — `file_seen`/`commit_seen`**: because `hunk_new_range` now returns a
  range for `new_count == 0` hunks, `file_new_ranges` includes pure-deletion
  hunks, so a whole-file deletion is no longer trivially "fully seen" — it must be
  marked. Delete-only test fixtures must mark the deletion before expecting a
  fully-seen file.
- **Empty new file edge**: a whole-file deletion has no new-file line; the
  synthetic anchor is `1`. For a committed deletion the range adapter records
  `{1,1}` fine. A delete-at-worktree (floating commit) has no content to hash at
  line 1; flag during implementation if such a fixture misbehaves and special-case
  it (e.g. hash the empty string or fall back to a range mark).

### Invariants

- **Index stability**: a hunk's `row_map` index must remain its index into the
  file's hunk list (`file.hunks` / `cf.hunks`). We partition only the *render
  order*, never the underlying list, and `cf.hunks` is set to `cf.raw.hunks` so
  `combined_tuples`/`mark_visual_range`/`comment_anchor` keep working unchanged.
- **Default-collapsed seen section**: a missing override means collapsed. This is
  the OPPOSITE default from files (collapsed iff fully seen). It is read inline in
  `build()`; no `apply_collapse` change is needed because the seen section is not
  a model field on commit/file — it is derived purely from `self.collapse`.
- **Collapse persistence**: seen-section overrides live in `self.collapse`
  (process memory via `views[key]`), so they survive `reload()` and reopen and are
  never written to disk — identical to existing collapse keys.
- **Seen-section header is collapse-only**: pressing `m` (toggle_seen), `c`
  (comment), or `<CR>` (jump) on it must be a no-op; only `=` acts on it. Rows
  *inside* the section are ordinary hunk/line rows, so `m`/`c`/visual-mark on them
  behave normally (un-seeing a line there moves its hunk back to the main body on
  the next render — desirable).
- **Markability unchanged**: a combined new line with no provenance owner was
  already non-markable (`combined_tuples` skips it); treating it as "not seen"
  keeps its hunk in the main body forever, matching today's behavior.

### Known tradeoff (hunk granularity — must be accepted)

Hunk-level seen means a **mixed hunk** (some new lines seen, some not) stays fully
in the main body. Verified: the test fixture `y.txt` (changes at lines 2 and 7 of
8) is a SINGLE merged raw hunk under default 3-line context, so once L2 is marked
seen, L2 is NO LONGER elided (it shares its hunk with the unseen L7). The current
tighter re-diff elides L2 sub-hunk; the new design does not. This is inherent to
the user's chosen hunk-granularity definition and must be reflected in the tests
(see test changes). Files whose changes are far enough apart to form separate
hunks get the clean per-hunk seen/unseen split.

## Stages

### Stage 1 — data-model additions (keys + hunk predicate)

- Goal: helpers exist for the new collapse keys and the seen test, no behavior
  change yet.
- Add near lines 84-86:
  - `local function seen_key(sha, path) return "s:" .. sha .. "\0" .. path end`
  - `local function cseen_key(path) return "cs:" .. path end`
- Add a module-level pure helper `hunk_anchor_lnums(hunk)` (near `hunk_new_range`,
  ~line 135) returning the hunk's anchor new-file lines:
    ```
    local function hunk_anchor_lnums(hunk)
      local out = {}
      for _, dl in ipairs(hunk.lines) do
        if dl.new_lnum then out[#out+1] = dl.new_lnum end
      end
      if #out == 0 and hunk.new_start then
        out[1] = math.max(hunk.new_start, 1)  -- pure-deletion synthetic anchor
      end
      return out
    end
    ```
- Add `hunk_is_seen(hunk, resolve)`: true iff the hunk has >=1 anchor line and
  every anchor resolves to an adapter reporting `is_seen`:
    ```
    local function hunk_is_seen(hunk, resolve)
      local anchors = hunk_anchor_lnums(hunk)
      if #anchors == 0 then return false end
      for _, ln in ipairs(anchors) do
        local ad, kl = resolve(ln)
        if not ad or not ad.is_seen(kl) then return false end
      end
      return true
    end
    ```
- Also extend `hunk_new_range` (line 135) so pure-deletion hunks expose their
  synthetic anchor as a markable range, making the deletion markable via the
  normal `target_ranges`/`target_groups`/`combined_tuples` paths:
    ```
    local function hunk_new_range(hunk)
      if hunk.new_count and hunk.new_count > 0 then
        return { hunk.new_start, hunk.new_start + hunk.new_count - 1 }
      end
      if hunk.new_start then local a = math.max(hunk.new_start, 1); return { a, a } end
      return nil
    end
    ```
- Verification: lua loads; existing tests still pass (helpers unused so far).

### Stage 2 — unified body renderer, commits scope first

Lowest-risk: commits scope render currently shows everything, so only the seen
section is *added*; no existing commits-scope assertion should break.

- In `Session:build()` (345-444), replace the inner `emit_file_body` (358-376)
  with two closures that share `emit`/`comments`/`self`:
  - `emit_hunk(hunk, hi, target_base, resolve)`: emit `hunk.header` with target
    `extend(target_base,{hunk=hi})`; for each `li,dl` emit `marker..dl.text` with
    target `extend(target,{line=li})`; compute hl from kind, override to
    `GleanSeen` when `resolve(dl.new_lnum)` is seen; push comments via the same
    `(ad, key_lnum)`. This reproduces today's per-line logic for BOTH scopes.
  - `emit_file_body(file, target_base, resolve, seen_ck)`:
    ```
    local seen_idx, unseen_idx = {}, {}
    for hi, hunk in ipairs(file.hunks) do
      if hunk_is_seen(hunk, resolve) then seen_idx[#seen_idx+1]=hi
      else unseen_idx[#unseen_idx+1]=hi end
    end
    for _, hi in ipairs(unseen_idx) do emit_hunk(file.hunks[hi], hi, target_base, resolve) end
    if #seen_idx > 0 then
      local c = self.collapse[seen_ck]; if c == nil then c = true end
      local chev = c and CHEVRON_CLOSED or CHEVRON_OPEN
      emit(("  %s ✓ seen (%d hunks)"):format(chev, #seen_idx),
        vim.tbl_extend("force", target_base, { seen = true }), "GleanSeen")
      if not c then
        for _, hi in ipairs(seen_idx) do emit_hunk(file.hunks[hi], hi, target_base, resolve) end
      end
    end
    ```
- Update the commits-scope call site (393-396):
    ```
    local adapter = self:adapter_for(commit, file.path)
    local resolve = function(ln) return adapter, ln end
    emit_file_body(file, { commit = ci, file = fi }, resolve, seen_key(commit.sha, file.path))
    ```
- Goal: in commits scope, an expanded partially-seen file shows unseen hunks then
  a collapsed `✓ seen (N hunks)` row that expands on `=`.
- Verification:
  - Behavior: seen hunks group under a collapsible header in commits scope.
  - Setup: fixture repo, commits scope, mark one hunk of a multi-hunk file seen.
  - Actions: render; toggle the seen-section row; render again.
  - Expected: header `✓ seen (1 hunks)` present and collapsed by default; the
    seen hunk's `+`-lines hidden until expanded, then visible; unseen hunks always
    visible. All existing commits-scope assertions still pass (no seen-section
    appears unless a hunk is fully seen in an expanded file).

### Stage 3 — combined scope on raw hunks

- Replace `Session:compute_combined()` (251-316) with the thin version:
    ```
    function Session:compute_combined()
      local out = {}
      for _, raw in ipairs(self.files) do
        local cov = self.collapse[cfile_key(raw.path)]
        if cov ~= nil then raw.collapsed = cov end
        out[#out+1] = { path = raw.path, kind = raw.kind, hunks = raw.hunks, raw = raw }
      end
      return out
    end
    ```
- Replace the combined render block in `build()` (402-440) with file-header +
  shared body:
    ```
    self.combined_files = self:compute_combined()
    for fi, cf in ipairs(self.combined_files) do
      local chevron = cf.raw.collapsed and CHEVRON_CLOSED or CHEVRON_OPEN
      local kind = cf.kind and (" [" .. cf.kind .. "]") or ""
      emit(chevron .. " " .. cf.path .. kind, { cfile = fi }, "GleanFileHeader")
      if not cf.raw.collapsed then
        local prov = self:provenance(cf.path)
        local resolve = function(ln)
          local p = prov[ln]; if not p then return nil end
          return self:combined_adapter(p.sha, cf.path), p.orig_lnum
        end
        emit_file_body(cf, { cfile = fi }, resolve, cseen_key(cf.path))
      end
    end
    ```
  (cf has `.hunks == cf.raw.hunks`, so `emit_file_body` iterating `file.hunks`
  works.)
- Remove now-dead `Session:tighter_diff` (239-246) and `Session:commit_index`
  (226-237); drop the `self._cidx = nil` line in `reload()` (865+). Keep
  `git:range_diff` in `git.lua`.
- Decision on combined file header: keep it as `▾ path` (do NOT add a ✓ fmark).
  Rationale: avoids breaking the many `▾ <file>` assertions and the seen section
  already signals seen-ness. A fully-seen combined file renders as `▾ path` +
  collapsed `✓ seen (N hunks)`. (Optional follow-up: add a `✓` fmark and/or
  auto-collapse fully-seen files for parity with commits scope — out of scope.)
- Goal: combined scope shows seen hunks in a collapsible per-file section instead
  of eliding them; no `seen up to` marker; no `✓ path ⟶` line.
- Verification:
  - Behavior: marking a combined file's only hunk seen tucks it into a collapsed
    seen section; reopen preserves it.
  - Setup: f.txt fixture (1 hunk, TWO@c1 + THREE@c2), combined scope.
  - Actions: `toggle_seen` on the file header; render; reopen.
  - Expected: file header still `▾ f.txt`; a `✓ seen (1 hunks)` row present;
    `+TWO`/`+THREE` hidden (section collapsed); reopen identical. Owner routing
    unchanged (TWO->c1 range, THREE->c2 range still asserted via the store).

### Stage 4 — collapse + action guards

- `Session:toggle_collapse` (508-531): handle the seen target FIRST in each scope,
  then drop the `not cf.fully_seen` guard.
    ```
    if self.scope == "commits" then
      local commit = self.commits[target.commit]
      if target.seen then
        local file = commit.files[target.file]
        local k = seen_key(commit.sha, file.path)
        local cur = self.collapse[k]; if cur == nil then cur = true end
        self.collapse[k] = not cur
      elseif target.file then ... (unchanged file toggle)
      else ... (unchanged commit toggle) end
    else
      if target.seen then
        local cf = self.combined_files[target.cfile]
        local k = cseen_key(cf.path)
        local cur = self.collapse[k]; if cur == nil then cur = true end
        self.collapse[k] = not cur
      elseif target.cfile then
        local cf = self.combined_files[target.cfile]
        if cf then cf.raw.collapsed = not cf.raw.collapsed
          self.collapse[cfile_key(cf.path)] = cf.raw.collapsed end
      end
    end
    ```
- `Session:toggle_seen` (597): add, right after `if not target then return end`:
  `if target.seen then return end`. This stops `m` on the seen header from marking
  the whole file (its target has `file`/`cfile` set but no `hunk`).
- `comment_anchor` (725) and `jump_target` (764) already bail when `not target.line`,
  so `c`/`<CR>` on the seen header are already no-ops — no change needed.
- Goal: `=` toggles the seen section open/closed and persists across reload/reopen;
  `m`/`c`/`<CR>` on the header do nothing.
- Verification:
  - Behavior: seen-section collapse persists across reload and reopen; header is
    inert to seen/comment.
  - Setup: a file with a seen section, in each scope.
  - Actions: toggle the section open; `reload()`; reopen; press `m` on the header.
  - Expected: open/closed state preserved both times; store unchanged after `m`.

### Stage 5 — test updates

- Goal: suite reflects the new rendering. Run `nvim -l nvim/lua/glean/init_test.lua`.
- The breaking assertions and their replacements are listed in the next section.
- Add new positive coverage: a commits-scope seen-section test, and a combined
  two-separate-hunks fixture that exercises the section cleanly.

## Concrete edit locations (init.lua)

| Location | Function / lines | Change |
| --- | --- | --- |
| key helpers | `commit_key`..`cfile_key` 84-86 | add `seen_key`, `cseen_key` |
| range helper | `hunk_new_range` 135 | synthetic anchor for `new_count == 0` |
| predicate | near `hunk_new_range` ~135 | add `hunk_anchor_lnums` + `hunk_is_seen` |
| combined mark | `Session:combined_tuples` 318 | deletion fallback via reverse-blame attribution |
| git helper | `git.lua` new `Git:blame_reverse` | map deleted base lines -> deleting commit (combined scope) |
| del provenance | new `Session:del_provenance(path)` | cached reverse-blame, keyed by target |
| dead code | `Session:commit_index` 226-237 | remove |
| dead code | `Session:tighter_diff` 239-246 | remove |
| combined model | `Session:compute_combined` 251-316 | replace with thin pass |
| renderer | `Session:build` `emit_file_body` 358-376 | split into `emit_hunk` + partitioning `emit_file_body` |
| commits call | `build` 393-396 | pass `resolve` + `seen_key(...)` |
| combined render | `build` 402-440 | file header + `emit_file_body(cf, {cfile=fi}, resolve, cseen_key)` |
| render cursor | `Session:render` 446+ | unchanged |
| collapse | `Session:toggle_collapse` 508-531 | add `target.seen` branch per scope; drop `fully_seen` guard |
| seen | `Session:toggle_seen` 597 | add `if target.seen then return end` |
| reload | `Session:reload` 865+ | drop `self._cidx = nil` (only if `commit_index` removed) |

No change needed: `mark_visual_range` (653),
`comment_anchor` (725), `jump_target` (764) — all index `cf.hunks == cf.raw.hunks`
and bail on non-line targets.

## Test assertions that break (init_test.lua) and their replacements

All counts verified against the fixtures (each is a single merged hunk).

1. Line 206 `combined: f.txt fully-seen row` — `joined:find("✓ f.txt")`.
   -> file is now `▾ f.txt` + collapsed seen section. Replace with:
   `joined:find("✓ seen (1 hunks)")` present AND `joined:find("▾ f.txt")` present.
   The adjacent `f.txt body elided` (`\n+TWO` == nil) STILL HOLDS (section
   default-collapsed) — keep it.
2. Line 211 `combined reopen: f.txt still fully seen` — `joined2:find("✓ f.txt")`.
   -> `joined2:find("✓ seen")` present. (`▾ g.txt` assertion on the next line keeps
   passing — g.txt still has an unseen hunk.)
3. Line 268 `follow-up: x.txt fully seen after c2` — `j3:find("✓ x.txt")`.
   -> `j3:find("✓ seen")` present (x.txt's single B2 hunk now seen -> section).
4. Lines 300-302 the y.txt re-diff block:
   - `seen up to marker shown` (300) -> REPLACE. Because y.txt is one merged hunk
     mixing seen L2 + unseen L7, there is NO seen section. Assert instead:
     `mixed hunk: no seen section` => `joined:find("✓ seen") == nil`.
   - `L7 (unseen) shown` (301) -> KEEP (still in main body).
   - `L2 hunk elided` (302) `\n+L2` == nil -> NOW FALSE. Replace with
     `mixed hunk: L2 still shown (shares hunk with unseen L7)` =>
     `joined:find("\n+L2") ~= nil`.
   - RECOMMENDED: also rework this fixture to changes at lines 2 and 10 of an
     11-line file (gap >= 7 unchanged lines) so they form TWO hunks; then it
     cleanly tests "L2 hunk -> collapsed seen section, L7 hunk -> main body":
     `joined:find("✓ seen (1 hunks)")` present, `\n+L2` == nil (collapsed),
     `\n+L7` ~= nil. This restores meaningful seen-section coverage in combined.
5. Lines 472 / 487 / 491 the wt-combined m.txt block (`✓ m.txt`):
   - 472 `not yet fully seen` (`✓ m.txt` == nil) -> `joined:find("✓ seen") == nil`
     (nothing seen yet; `+B` and `+D` still asserted shown).
   - 487 `m.txt fully seen` -> `jseen:find("✓ seen (1 hunks)")` present (B@c1 + D@WT
     both marked -> the single hunk is seen). The store-routing asserts above it
     (range-seen on c1, hash block on WORKTREE) are unchanged — keep.
   - 491 reopen -> `j2:find("✓ seen")` present.

Unaffected (re-confirm they still pass): all commits-scope seen/collapse/comment
tests (seen section only appears in EXPANDED partially-seen files; fully-seen
files auto-collapse via `apply_collapse` as before), the worktree commits-scope
`w.txt ✓` file-header test (checks the FILE header mark, not a fully-seen row),
jump tests, buffer-reuse test, and the count-based collapse test (its shared
`state_dir` is never marked seen).

Caveat for new/edited tests: the seen-section header target is `{file/cfile,
seen=true}` with NO path in its text. Predicates that match file headers purely by
`t.file and not t.hunk` without a path/text check could accidentally match it;
existing predicates also test the line text (path), so they are safe — keep that
pattern.

## Open questions / things to verify during implementation

- Exact seen-header string/indent (`  ▾ ✓ seen (N hunks)`) is cosmetic; tests
  should match on the stable substring `✓ seen (` rather than full spacing.
- Optional parity items deferred: a `✓` fmark on combined file headers and
  auto-collapsing fully-seen combined files (would re-add `apply_collapse`-style
  defaulting for combined). Not required by the request.
- `git:range_diff` becomes unused by init.lua but retains its own test; leave it.
