# dotfiles magenta scripts

Magenta script package (discovered via `~/.magenta/scripts -> magenta-scripts`).

- **implement-plan** — implements a plan file stage by stage on a fresh branch.
  For each stage it spawns an agent to implement and commit the stage, then runs
  the code-review workflow over just that stage's changes and (if there are
  findings) spawns an agent to address them and commit.
- **code-review** — reviews a git changeset against the repo's
  `.github/instructions/*.instructions.md` (and `copilot-instructions.md`),
  spawning one review thread per applicable instruction file in parallel.

`magenta-sdk` is a gitignored symlink to `magenta.nvim/sdk` (created by Home
Manager activation). Tests: `npm install && npx vitest run`.
