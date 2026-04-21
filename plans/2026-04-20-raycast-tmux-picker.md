# Context

The goal is to build a unified tmux session picker that works across the host machine and one or more remote hosts (dev containers, SSH boxes), invoked via a Raycast hotkey, controlling a single Ghostty window.

## Design decisions (already made)

- **One Ghostty window** hosts all terminal work. Its child is always either a shell, a local `tmux` client, or an `ssh` session into a remote tmux.
- **No nested tmux.** The terminal is in exactly one tmux at a time (local or remote), or at a bare shell.
- **No dispatcher loop, no state files.** Raycast is stateless — each invocation inspects the Ghostty window's current foreground process and acts on it.
- **No cached remote sessions.** On every picker open, Raycast SSHes into each configured remote and runs `tmux list-sessions` live. SSH ControlMaster keeps this under ~100ms.
- **Raycast's native chooser UI** is used for selection (no fzf/terminal popup).
- **Transition mechanism:**
  - Always attach remote targets via `ssh -t host 'tmux new-session -A -s NAME'` so that tmux is ssh's direct child. When tmux detaches, the ssh process exits and the Ghostty window is back at the host shell. This is a precondition for the detach logic below.
  - Detach current tmux by sending `C-b d` keystrokes to the focused Ghostty window via AppleScript. Works uniformly:
    - Local tmux: detaches, shell returns.
    - Remote tmux (attached as above): tmux exits, ssh exits, host shell returns.
  - If the current state is `ssh_shell` (sitting at a remote shell with no tmux — e.g. a manually-started ssh, or a prior tmux session the user exited): send `exit⏎` to close the remote shell so ssh exits and we're back at the host shell.
  - Attach the chosen target by typing a command into Ghostty via AppleScript keystrokes:
    - local → `tmux attach -t <name>`
    - remote → `ssh -t <host> 'tmux new-session -A -s <name>'`
## Relevant files

- \`scripts/ta\` — current host-side session launcher. Will be simplified: it no longer needs the remote-session branch once Raycast drives transitions, but it remains useful for initial \`ta <path>\` invocations at a bare shell.
- \`scripts/tmux-session-using-fzf\` — current in-tmux picker. Will be deprecated once Raycast picker replaces it.
- \`~/.ssh/config\` — source of truth for known SSH hosts; the picker reads it to enumerate remotes.
- \`~/.config/ta/hosts\` (new) — optional override/allowlist of remote hosts to query (so we don't ssh to every alias).
- \`~/.config/raycast/extensions/...\` — Raycast extension directory. A new extension \`tmux-picker\` will be added here.

## Key types

Session record used by the picker:

\`\`\`ts
type SessionKind = "local" | "remote";

interface Session {
  kind: SessionKind;
  host?: string;          // undefined for local
  name: string;           // tmux session name
  windows: number;        // informational
  attached: boolean;      // informational
}
\`\`\`

Current Ghostty state, derived from the focused window's foreground process:

\`\`\`ts
type GhosttyState =
  | { kind: "shell" }                                           // bare host shell
  | { kind: "local_tmux"; session: string }                     // attached to local tmux
  | { kind: "ssh_tmux"; host: string; remoteSession: string }   // ssh'd, tmux is ssh's direct child
  | { kind: "ssh_shell"; host: string };                        // ssh'd but at a remote shell (no tmux)
\`\`\`

# Implementation

- [ ] **Scaffold the Raycast extension**
  - \`npm create raycast@latest\` inside \`~/.config/raycast/extensions/tmux-picker\` (or similar path).
  - Single no-view command \`switch-tmux-session\` that runs the full flow.
  - Add extension to the dotfiles repo (symlinked or copied).
  - Manual test: invoking the command shows "Hello world" toast.

- [ ] **Implement host configuration loading**
  - Read \`~/.config/ta/hosts\` if present (newline-separated list of SSH aliases).
  - If absent, fall back to parsing \`~/.ssh/config\` for \`Host\` entries, excluding patterns (\`*\`) and wildcards.
  - Expose \`getHosts(): string[]\`.
  - Test:
    - Behavior: returns the explicit list when the override file exists.
    - Setup: write a temp \`hosts\` file with \`dev\\nprod\`.
    - Actions: call \`getHosts()\`.
    - Expected: \`["dev", "prod"]\`.
    - Assertions: array equality.

- [ ] **Implement session enumeration**
  - \`listLocalSessions()\`: shell out to \`tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}'\`; return \`Session[]\` with \`kind: "local"\`.
  - \`listRemoteSessions(host)\`: shell out to \`ssh -o BatchMode=yes -o ConnectTimeout=2 \$host 'tmux list-sessions -F "…"'\`; return \`Session[]\` with \`kind: "remote", host\`.
  - \`listAllSessions()\`: parallelize local + all remote via \`Promise.all\`, concatenate results, ignore hosts that fail (log to Raycast error toast if all fail).
  - Ensure SSH ControlMaster is configured in \`~/.ssh/config\` for low-latency reuse (document the required stanza in the plan, but config itself lives in dotfiles repo).
  - Test:
    - Behavior: aggregates local and remote sessions.
    - Setup: mock \`exec\` to return canned output for \`tmux list-sessions\` locally and for one remote host.
    - Actions: call \`listAllSessions(["dev"])\`.
    - Expected: array containing local and remote entries with correct fields.
    - Assertions: length and field checks.

- [ ] **Implement Ghostty state inspection**
  - AppleScript: get the frontmost Ghostty window's unix PID: \`osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true'\`.
  - Walk descendants via \`ps -A -o pid,ppid,command\` until reaching a leaf (the foreground child of the shell).
  - Classify:
    - Executable basename \`tmux\` → \`local_tmux\`; extract session from \`tmux display-message -p -t \$pane\` or from the shell's tty via \`tmux list-clients\`.
    - Executable \`ssh\` → \`ssh\`; parse host from argv. If the ssh command is \`ssh -t host '… tmux new-session -A -s NAME …'\`, extract \`NAME\` as \`remoteSession\`.
    - Otherwise → \`shell\`.
  - Test:
    - Behavior: correctly classifies a simulated process tree.
    - Setup: mock \`ps\` output with a known tree (shell → tmux client).
    - Actions: call \`getGhosttyState()\`.
    - Expected: \`{ kind: "local_tmux", session: "src" }\`.
    - Assertions: field equality.

- [ ] **Implement the picker UI**
  - Raycast \`List\` component showing all sessions with sections for "Local" and each remote host.
  - Accessory shows attached state and window count.
  - On submit: call \`transitionTo(session)\` (implemented in next step).
  - Manual test: command opens, shows sections, responds to keyboard.

- [ ] **Implement the transition**
  - \`transitionTo(target: Session)\`:
    1. Read current \`GhosttyState\`.
    2.     2. Issue the detach appropriate to the state:
       - `local_tmux` or `ssh_tmux`: send `C-b d` keystrokes to the focused Ghostty window.
       - `ssh_shell`: send `exit⏎` to close the remote shell (ssh exits with it).
       - `shell`: no-op.
 \`shell\`: send \`ctrl-b d\` to the focused Ghostty window via \`osascript\` (\`tell application "System Events" to keystroke "b" using control down\` then \`keystroke "d"\`).
    3. Poll the Ghostty foreground process up to 1s at 50ms intervals until it's a shell (parent of the original tmux/ssh, no more child). Bail with an error toast on timeout.
    4. Focus Ghostty window (\`tell application "Ghostty" to activate\`).
    5. Type the attach command followed by \`⏎\` via \`osascript\` keystroke:
       - local → \`tmux attach -t <name>\`
       - remote → \`ssh -t <host> 'tmux new-session -A -s <name>'\`
  - Test:
    - Behavior: given a state and a target, the correct AppleScript sequence is produced.
    - Setup: stub the AppleScript runner with a recorder.
    - Actions: call \`transitionTo({ kind: "remote", host: "dev", name: "main" })\` with state \`local_tmux\`.
    - Expected: recorded calls include a \`C-b d\` keystroke, then a wait, then the ssh command typed with newline.
    - Assertions: recorded call order and arguments.

- [ ] **Wire up the Raycast hotkey**
  - In Raycast preferences, assign a global hotkey (e.g., \`cmd-shift-j\`) to \`switch-tmux-session\`.
  - Document the hotkey in \`context.md\`.
  - Manual test: press hotkey from anywhere; picker appears; selecting a session transitions the Ghostty window.

- [ ] **Simplify \`scripts/ta\`**
  - Remove the remote-session branch (\`create_remote_session\`, \`is_remote_session\`) — now handled by the picker.
  - Keep the local-directory branch (\`ta <path>\`) for shell-level session creation.
  - Update \`context.md\` to describe the new architecture.
  - Manual test: \`ta ~/src/dotfiles\` still creates/attaches a local tmux session.

- [ ] **Deprecate \`scripts/tmux-session-using-fzf\`**
  - Remove the in-tmux binding that invokes it from the tmux config.
  - Delete the script (or leave a note pointing to the Raycast extension).

- [ ] **Document**
  - Add a section to \`context.md\` describing:
    - The Raycast extension and hotkey.
    - Required \`~/.ssh/config\` ControlMaster stanza for low-latency session listing.
    - Optional \`~/.config/ta/hosts\` format.
    - How to add a new remote host.

## Open questions

- **Identifying the current local tmux session**: simplest is to scan \`tmux list-clients\` and find the client whose \`client_tty\` matches the Ghostty window's tty. The tty is reachable via \`ps\` on the shell process.
- **Typing robustness**: AppleScript keystroke relies on the system keyboard layout. For user names with punctuation, prefer \`cliclick t:<text>\` if issues arise.
- **Shell prompt detection**: polling for the child to go away is simpler and good enough versus detecting a prompt heuristically.
