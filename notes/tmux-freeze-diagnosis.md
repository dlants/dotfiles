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

## Related

Upgraded tmux 3.6b → 3.7a (see `nix/common.nix` tmux overlay) hoping for a
fix, but the 3.6b→3.7a changelog has no entry explicitly describing a
copy-mode freeze/hang fix. Closest related items: control-client hang fix
(issue 5049), run-shell hang fix (issue 5037), and scrollbar option caching
(issue 5298) which could help if the "freeze" is really a slow redraw. If it
recurs after the upgrade, the diagnostics above should confirm whether it's
the same issue.
