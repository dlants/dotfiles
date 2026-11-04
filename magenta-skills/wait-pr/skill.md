---
name: wait-pr
description: Block until a GitHub PR (github.com/dlants) has all green checks, a new failing check, or a new comment. Use when the user asks to wait on / watch a PR.
---

```bash
node --experimental-transform-types ~/.magenta/watchers/github-pr/wait-pr.ts <pr-url> --until green|new-failure|new-comment [--timeout SECONDS]
```

- `green`: no pending and no failing checks (returns immediately if already green).
- `new-failure`: a check is failing that was not failing when the wait started.
- `new-comment`: an issue/review comment appeared that was not there when the wait started.

Exit 0 prints the PR's current state (checks + comments); exit 2 is timeout; exit 1 is an error (watcher unavailable, PR not found, auth). It connects to (or spawns) the shared `github-pr` watcher, so it does not add extra GitHub polling when magenta already tracks the PR. Run it with a generous bash timeout, or in the background, since CI can take a while.
