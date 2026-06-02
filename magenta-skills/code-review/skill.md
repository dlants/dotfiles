---
name: code-review
description: Review a changeset using a repo's Copilot review instructions. Use when asked to review a PR, branch, diff, or set of local changes.
---

## Step 1: Gather the applicable review prompts

Run the script with a start identifier and an optional stop identifier:

```bash
pkgx uv run <skilldir>/scripts/gather_prompts.py <start> [stop] --repo <path>
```

- `<start>` — required git identifier (commit, branch, or tag) to diff from.
- `[stop]` — optional ending identifier. **If omitted**, the diff runs from `<start>` to the working tree and also includes staged, unstaged, and untracked files — i.e. everything dirty in the working dir.
- `--repo <path>` — repository to inspect (default: current directory).

The script prints, one per line, the path of every instruction file that applies to the changeset: each `.github/instructions/*.instructions.md` whose `applyTo` globs match at least one changed file, plus the repository-wide `.github/copilot-instructions.md`. Files without an `applyTo`, or with `excludeAgent: code-review`, are skipped — matching Copilot's own selection rules.

## Step 2: Spawn parallel review agents

Spawn one review agent per prompt file returned in Step 1, all in parallel, using the `default` subagent type. For each agent:

- Pass the prompt file as a **context file** (do not paste its contents into the prompt).
- Tell the agent the repo path and the diff range (`<start>` and optional `[stop]`).
- The sharedPrompt should ask subagents to review the actual diff (`git diff <start> [stop]`) **only from the perspective of its single prompt file**, reporting concrete, actionable findings with file/line references, and not restating the guidelines.

## Step 3: Consolidate

Present the findings to the user, grouped or deduplicated as appropriate.
