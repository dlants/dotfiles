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

- \`scripts/ta\` — current host-side session launcher. Left untouched; it still drives \`ta <path>\` and \`ta dev\` from a bare shell. The Raycast picker is an additional, parallel entry point, not a replacement.
- \`scripts/tmux-session-using-fzf\` — current in-tmux picker. Will be deprecated once Raycast picker replaces it.
- \`raycast/tmux-picker/\` (new, in dotfiles repo) — source of the Raycast extension. Symlinked into \`~/.config/raycast/extensions/tmux-picker\` via \`nix/darwin.nix\` using \`mkOutOfStoreSymlink\` (same pattern as \`tmux.conf\`, \`scripts/ta\`, etc.). Remote hosts are hardcoded inside the extension (currently just \`dev\`); no separate config file.
- \`nix/darwin.nix\` — macOS home-manager config; gains a new \`home.file\` entry that symlinks the extension directory into Raycast's extensions folder.

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

- [ ] **Scaffold the Raycast extension in the dotfiles repo**
  - Create \`raycast/tmux-picker/\` in the dotfiles repo with a hand-rolled layout (do not use \`npm create raycast@latest\` — its scaffolding is overkill for this single-command extension).
  - Toolchain:
    - **Node 24** as the runtime. No experimental flags needed; native TS support is irrelevant here because we ship a bundle.
    - **TypeScript** for source files under \`src/\`.
    - **esbuild** to bundle each command entry point into a single CommonJS file under \`dist/\` (the format Raycast's extension loader expects).
  - Files to create:
    - \`package.json\` — Raycast extension manifest. Include the \`commands\` array (one no-view command \`switch-tmux-session\`), \`main\`/\`commands[].mode\` fields per Raycast's schema, \`engines.node: ">=24"\`, devDeps on \`typescript\`, \`esbuild\`, and \`@raycast/api\` as a regular dep.
    - \`tsconfig.json\` — \`target: es2022\`, \`module: commonjs\`, \`moduleResolution: node\`, \`strict: true\`, \`jsx: react-jsx\` (Raycast UI uses JSX).
    - \`build.mjs\` — esbuild script: bundles \`src/switch-tmux-session.tsx\` → \`switch-tmux-session.js\` at the package root (Raycast loads JS from the path declared in the manifest), with \`platform: "node"\`, \`format: "cjs"\`, \`target: "node24"\`, externals for \`@raycast/api\` and any native deps Raycast injects.
    - \`src/switch-tmux-session.tsx\` — placeholder command that shows a "Hello world" toast.
  - npm scripts: \`build\` (single esbuild run), \`dev\` (esbuild watch + Raycast's extension reload — likely just \`--watch\`), \`typecheck\` (\`tsc --noEmit\`).
  - Add a \`home.file\` entry to \`nix/darwin.nix\` that symlinks the extension directory into Raycast's extensions folder, e.g.:
    \`\`\`nix
    home.file.".config/raycast/extensions/tmux-picker".source =
      config.lib.file.mkOutOfStoreSymlink "\${dotfilesDir}/raycast/tmux-picker";
    \`\`\`
  - Run \`home-manager switch\` to materialize the symlink, then \`npm install && npm run build\` inside the extension directory.
  - Manual test: invoking the command in Raycast shows the "Hello world" toast; editing the source and re-running \`npm run build\` is reflected on next invocation.

- [ ] **Hardcode the remote host list**
  - Define a constant \`REMOTE_HOSTS = ["dev"]\` in a shared module (e.g. \`src/hosts.ts\`).
  - Expose \`getHosts(): string[]\` returning that constant. Trivial; no test needed.
  - Adding a new remote host later means editing this file and rebuilding.

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


- [ ] **Deprecate \`scripts/tmux-session-using-fzf\`**
  - Remove the in-tmux binding that invokes it from the tmux config.
  - Delete the script (or leave a note pointing to the Raycast extension).

- [ ] **Document**
  - Add a section to \`context.md\` describing:
    - The Raycast extension and hotkey.
    - Required \`~/.ssh/config\` ControlMaster stanza for low-latency session listing.
    - How to add a new remote host (edit \`REMOTE_HOSTS\` in \`raycast/tmux-picker/src/hosts.ts\` and rebuild).

## Open questions

- **Identifying the current local tmux session**: simplest is to scan \`tmux list-clients\` and find the client whose \`client_tty\` matches the Ghostty window's tty. The tty is reachable via \`ps\` on the shell process.
- **Typing robustness**: AppleScript keystroke relies on the system keyboard layout. For user names with punctuation, prefer \`cliclick t:<text>\` if issues arise.
- **Shell prompt detection**: polling for the child to go away is simpler and good enough versus detecting a prompt heuristically.
