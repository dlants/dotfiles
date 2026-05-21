# Dotfiles TODO

## Git cleanup (dirty working tree)

~~The repo had uncommitted reorganization work. Committed in logical chunks (2026-04-30).~~

### Rename: `notes/` → `docs/`

- [x] `git rm notes/clipboard-setup.md notes/nvim-diagnostics.md notes/nvim-pr-review.md notes/ssh-tmux-paste.md`
- [x] `git add docs/`
- [x] Commit: `82b99b3` "chore: rename notes/ to docs/, add setup and config guides"

### Removed files

- [x] `git rm README.md` — deleted (context.md serves as the repo overview now)
- [x] `git rm denis-config.md` — deleted (was upstream reference, no longer needed)
- [x] `git rm initial-setup.md` — deleted (replaced by docs/neovim-setup-guide.md)
- [x] `git rm nvim/init-term.lua` — deleted (terminal-specific init, no longer used)
- [x] Commit: `856d6c0` "chore: remove old docs and unused init-term.lua"

### New directory: `archive/`

- [x] `git add archive/`
- [x] Commit: `c9d617f` "chore: add archive/ for retired configs (vscode-integration-guide)"

### Modified configs

- [x] Review `nvim/init.lua` changes — vertical resize keymaps, ESC noh, :Ghpr/:Ghprv commands
- [x] Review `nvim/lua/plugins/plugins.lua` changes — catppuccin theme, zenbones commented, fugitive no-merges
- [x] Review `context.md` changes — trimmed to concise repo overview
- [x] Commit: `eb07d12` "feat: update neovim config, switch to catppuccin, trim context.md"

## Config tasks

- [ ] Install Hammerspoon (`brew install hammerspoon`) — configured but app not installed
- [ ] Decide on fish as default shell or remove from active config
- [x] ~~Sync with upstream~~ — **Decision (2026-04-30):** don't rebase/merge upstream wholesale. `mine` has diverged enough to be its own config. Keep `upstream` remote for browsing (`git fetch upstream`) and cherry-pick selectively if something interesting comes up. Never `git merge upstream/main`.

## Future ideas

- [ ] Consider moving personal knowledge base (plans, skills, reading-list, learnings) out of `~/.claude/` into a dedicated portable directory
