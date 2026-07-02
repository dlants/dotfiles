# zsh + tmux + nvim Rendering Corruption

## The Problem

nvim renders incorrectly when run as: zsh → tmux → nvim.
- fish → tmux → nvim: works fine
- zsh → nvim (no tmux): works fine
- zsh → tmux → nvim: broken

So the bug is specific to the combination of zsh's shell integration and
tmux's passthrough of terminal escape sequences.

## What We've Tried / Ruled Out

### zsh-vi-mode plugin (nix/common.nix)

Initially suspected the `zsh-vi-mode` zsh plugin (via `common.nix`) of
corrupting terminal state with its cursor-shape escape sequences. Disabled
it (commented out the plugin block, added `ZVM_CURSOR_STYLE_ENABLED=false`
in `envExtra`) and confirmed via a fresh interactive shell that:
- `~/.zshrc` has no references to `zvm`/`zsh-vi-mode`
- no `zvm_*` functions are defined
- `zvm_init` does not exist
- no `zle-line-init` widget is hooked

**Conclusion: zsh-vi-mode is fully disabled and was not the (sole) cause.**
Rendering still broken.

### TERM inside tmux

`TERM=xterm-ghostty` inside tmux is expected/intentional — set explicitly by
`set -g default-terminal "xterm-ghostty"` in `tmux.conf`. Terminfo entry for
`xterm-ghostty` exists and looks normal (proper `smcup`/`rmcup`, no unusual
`Ms`/sync capabilities). Not the culprit.

### zsh config (plugins, autosuggestion, syntax-highlighting, initContent)

Temporarily disabled in `nix/common.nix`: `autosuggestion.enable`,
`syntaxHighlighting.enable`, the `fzf-tab`/`zsh-history-substring-search`
plugins, and all of `initContent` (carapace, keybindings, platform config).
Left `starship` enabled. Rebuilt via `home-manager switch`.

**Result: still broken.**

### Shell itself (bash vs zsh)

Tried `tmux new-session bash` / `tmux new-window bash` to run bash instead of
zsh as the pane command (reusing the existing tmux server/session).

**Result: still broken.** This suggests the bug may not be shell-specific at
all — need to verify by fully killing the tmux server (`tmux kill-server`)
and starting a completely fresh session with bash, since reusing an existing
tmux server could carry over corrupted server-level state (terminal-overrides,
focus-events, etc.) regardless of the pane's shell.
### Ghostty's zsh shell-integration `cursor` feature (RULED OUT)

Ghostty's bundled zsh shell integration script
(`/Applications/Ghostty.app/Contents/Resources/ghostty/shell-integration/zsh/ghostty-integration`)
has a `cursor` feature, enabled when `GHOSTTY_SHELL_FEATURES` contains
`cursor`. It hooks `zle-line-init` / `zle-keymap-select` and writes raw
DECSCUSR cursor-shape escapes (`\e[1 q`, `\e[5 q`, etc.) directly to the
terminal fd on every keymap change (vi mode block vs. bar cursor), and
resets with `\e[0 q` in `preexec` before running external commands.

The script's own comment admits:

> This implementation leaks blinking block cursor into external commands
> executed from zle.

This matches our symptom pattern exactly:
- fish's integration doesn't have this same leak, so fish → tmux → nvim is fine
- zsh → nvim directly works because there's no tmux passthrough layer to
  desync the escape sequence timing
- zsh → tmux → nvim breaks because a stray/in-flight cursor-shape escape
  from zsh's keymap hooks can land in nvim's raw input stream instead of
  being cleanly consumed as a terminal control sequence, corrupting
  rendering

### Fix attempted

Edited `ghostty/config`:

```
- shell-integration-features = cursor,sudo,no-title
+ shell-integration-features = sudo,no-title
```

### Verification (not yet passing)

In a fresh zsh shell, check:

```sh
echo $GHOSTTY_SHELL_FEATURES
typeset -f _ghostty_zle_keymap_select >/dev/null && echo "cursor hook present" || echo "cursor hook absent"
```

Expected: `$GHOSTTY_SHELL_FEATURES` shows `sudo,no-title` (no `cursor`), and
"cursor hook absent".

**Actual result after config edit + new tab (no full Ghostty restart):**

```
cursor:blink,path,sudo
cursor hook present
```

Config reload (`ctrl+shift+,` / `reload_config`) does NOT appear to re-inject
`GHOSTTY_SHELL_FEATURES` into newly spawned shells — even new tabs still got
the old feature set (`cursor:blink,path,sudo`, which is actually Ghostty's
*default* feature set, not even what the old config explicitly said
(`cursor,sudo,no-title`) — suggesting this Ghostty instance wasn't even
picking up the file-based config for shell-integration-features in the
first place).

## ROOT CAUSE FOUND: tmux 3.7a regression

None of zsh, Ghostty shell-integration, or `tmux.conf` were at fault. The
actual culprit was a rendering regression in **tmux 3.7a** itself:

- `tmux -f /dev/null new-session bash` (stock tmux config, bash instead of
  zsh, fresh server) was still broken — ruling out shell and `tmux.conf`.
- Recalled that tmux had recently been upgraded to 3.7a via an explicit
  overlay pin in `nix/common.nix` (nixpkgs itself still ships plain 3.7).
- tmux 3.7b (a bugfix release for the 3.7 line) had just been released the
  day before this was diagnosed, suggesting a known-recent regression.
- Temporarily re-pinned the overlay in `nix/common.nix` to **tmux 3.6b**
  (fetched via `nix run nixpkgs#nix-prefetch-github -- tmux tmux --rev 3.6b`
  for the hash), ran `home-manager switch --flake .#macos`, fully killed the
  tmux server, and restarted.

**Result: rendering corruption is GONE.** Confirmed tmux 3.7a (or possibly
3.7 generally) is the root cause of the nvim rendering corruption.

## Follow-ups

- Consider trying 3.7b instead of 3.6b, since it's a bugfix release that may
  have already fixed this specific issue — would let us stay on a newer tmux.
- If staying on 3.6b, revert the "DEBUG" comments in `nix/common.nix` to
  make the pin permanent/intentional rather than look like a leftover debug
  hack.
- Consider filing an upstream tmux bug report with the repro (stock config +
  Ghostty + macOS) if 3.7b doesn't fix it.
