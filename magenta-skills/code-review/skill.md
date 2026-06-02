---
name: code-review
description: Review a changeset using a repo's Copilot review instructions. Use when asked to review a PR, branch, diff, or set of local changes. Generates a combined review prompt by matching .github/instructions/*.instructions.md applyTo globs against the changed files, then perform the review.
---

# Code Review

Use this skill to review changes in any repo that has Copilot review instructions (`.github/instructions/*.instructions.md` and/or `.github/copilot-instructions.md`).

## Step 1: Generate the review prompt

Run the script with a start identifier and an optional stop identifier:

```bash
pkgx uv run scripts/review_prompt.py <start> [stop] --repo <path>
```

- `<start>` — required git identifier (commit, branch, or tag) to diff from.
- `[stop]` — optional ending identifier. **If omitted**, the diff runs from `<start>` to the working tree and also includes staged, unstaged, and untracked files — i.e. everything dirty in the working dir.
- `--repo <path>` — repository to inspect (default: current directory).

The script prints a combined review prompt: the list of changed files, plus the body of every instruction file whose `applyTo` globs match at least one changed file. Repository-wide instructions (`.github/copilot-instructions.md`) are always included. Files without an `applyTo`, or with `excludeAgent: code-review`, are skipped — matching Copilot's own selection rules.

## Step 2: Perform the review

Read the generated prompt, then review the actual diff (`git diff <start> [stop]`) against the matched instructions. Report concrete, actionable findings with file/line references. Do not restate the guidelines back to the user.
