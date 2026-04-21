# PR Review: Using `gh` to get commits

Instead of using fugitive's `Gclog main...HEAD` to view PR commits, use:

```bash
# List commits on a PR (excludes merge commits in the output)
gh pr view <pr-number> --json commits --jq '.commits[] | "\(.oid[:11]) \(.messageHeadline)"'

# Include PR metadata
gh pr view <pr-number> --json title,headRefName,baseRefName,commits
```

This gives a cleaner view of the actual PR diff — just the commits that belong to the PR, with merge-from-main commits clearly visible so you can filter them out.
