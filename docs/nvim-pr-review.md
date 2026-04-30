# PR Review: Viewing Commits

Three ways to get the commit list for a PR, depending on what you want.

## 1. Fugitive `Gclog` (default — best ergonomics)

Mapped to `<leader>l`:

```vim
:Gclog --no-merges main..HEAD
```

Opens the commits in a quickfix-style action window. Jump between commits with `[q` / `]q` (or `:cnext` / `:cprev`); `<CR>` on an entry views that commit. Nicest way to move through commits interactively.

Note: plain `:Gclog main...HEAD` would include merge-from-main commits. The mapped form uses `main..HEAD` (double-dot = only commits on the PR branch) plus `--no-merges` to strip them.

Someday: get `gh pr view` results into the same quickfix pane so numbered PRs are jumpable the same way.

## 2. `gh pr view` — commits only, no merge commits

Wrapped as `:Ghpr [pr-number]` (pr number optional; defaults to the current branch's PR):

```vim
:Ghpr
:Ghpr 123
```

Equivalent CLI:

```bash
gh pr view <pr-number> --json commits --jq '.commits[] | "\(.oid[:11]) \(.messageHeadline)"'
```

The `gh` API excludes merge commits from the `commits` field, so this is just the commits that belong to the PR. Good for a quick terminal overview or piping into other tools.

## 3. `gh pr view` — with PR metadata

Wrapped as `:Ghprv [pr-number]`:

```vim
:Ghprv
:Ghprv 123
```

Equivalent CLI:

```bash
gh pr view <pr-number> --json title,headRefName,baseRefName,commits
```

Same commit list as (2), plus PR title and head/base branch names. Useful for scripting or sanity-checking you're looking at the right PR.
