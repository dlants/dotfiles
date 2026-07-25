# Diagnosing Tmux Freezes/Lockups

## The Problem

tmux occasionally locks up — sometimes with high CPU, sometimes not. Suspected
correlation with running neovim inside a pane, but not confirmed. On
2026-07-02, had to escalate from `pkill tmux` to `pkill -9 tmux` to recover,
per fish history. No macOS crash report was generated (`kill -9` and plain
hangs don't produce one in `~/Library/Logs/DiagnosticReports`).

## Before Killing It: Capture Diagnostics

### 1. Stack sample (most useful, no killing required)

```sh
sample <tmux-pid> 5 -f ~/tmux-sample.txt
```

or for a deeper/system-wide view:

```sh
sudo spindump <tmux-pid> -reveal -o ~/tmux-spindump.txt
```

Shows exactly which function/syscall it's stuck in.

### 2. Process state (not just CPU)

```sh
ps -o pid,stat,%cpu,wchan,command -p <tmux-pid>
```

`STAT` of `D` = stuck in uninterruptible I/O (disk/kernel), `R` = actually
spinning (matches high-CPU cases), `T`/`Z` = stopped/zombie.

### 3. Attach a debugger for a real backtrace

Works even if tmux isn't responding to keys:

```sh
lldb -p <tmux-pid>
(lldb) bt all
(lldb) detach
```

### 4. Check per-pane processes

Since nvim is suspected, check whether it's the tmux server itself pegged, or
a client pane / nvim subprocess:

```sh
ps -o pid,ppid,pcpu,command -t <tty>
top -o cpu
```

## If You Must Kill It

Prefer `kill -QUIT` or `kill -ABRT` over `-9` — `-9` gives zero forensics,
whereas QUIT/ABRT can produce a core dump for later analysis.

Check core dumps are enabled first:

```sh
ulimit -c
# if 0, enable (add to shell profile to persist):
ulimit -c unlimited
```

Core files land in `/cores/core.<pid>`, inspectable with `lldb --core`.

## Proactive: Enable Tmux's Own Verbose Logging

tmux can't retroactively log an already-running frozen server. To catch the
next occurrence, restart the server with verbose logging:

```sh
tmux -vv new-session ...
```

This writes `tmux-server-<pid>.log` / `tmux-client-<pid>.log` into the tmux
start directory (cwd), logging all client/server messages — useful for seeing
what tmux was doing right before it froze.

## Root Cause (found 2026-07-25)

Self-referential copy-mode keybinding. tmux.conf had:

```
bind-key -T copy-mode-vi C-h send-keys C-h
```

`send-keys` re-looks-up the key in the *target pane's current* key table. For a
pane in copy mode that table is `copy-mode-vi`, so the binding dispatched
itself, enqueuing a new command each time — an unbounded command queue, server
pegged at 100% CPU (`R` state) and unable to return to `server_loop` to service
clients (even `tmux list-sessions` from outside hangs).

Trigger: the root binding `bind-key -n C-h if-shell "$is_vim" 'send-keys C-h'`
only takes the send-keys branch when `ps` shows nvim/zsh on the pane tty —
hence the apparent nvim correlation. Pressing C-h in an nvim pane that was
scrolled into copy mode started the loop.

Signature in a `sample`/lldb backtrace:

```
server_loop -> cmdq_next -> cmd_send_keys_exec -> cmd_send_keys_inject_key
  -> window_copy_key_table -> key_bindings_dispatch -> cmdq_get_command
  -> cmdq_insert_after
```

with most cycles in malloc/`vasprintf` (`cmdq_insert_hook -> cmdq_add_format`,
and `cmd_print -> args_print` when the server's log level is > 1).

Fix: those copy-mode bindings now use `select-pane -L/-D/-U/-R` instead.

Unrelated leak found at the same time: `ctrl-b o` orphans its
`tmux-session-using-fzf` / `fzf-tmux` processes (dozens accumulated, some
outliving the server).

## Related

Upgraded tmux 3.6b → 3.7a (see `nix/common.nix` tmux overlay) hoping for a
fix, but the 3.6b→3.7a changelog has no entry explicitly describing a
copy-mode freeze/hang fix. Closest related items: control-client hang fix
(issue 5049), run-shell hang fix (issue 5037), and scrollbar option caching
(issue 5298) which could help if the "freeze" is really a slow redraw. If it
recurs after the upgrade, the diagnostics above should confirm whether it's
the same issue.
