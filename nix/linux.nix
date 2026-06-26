# Linux devcontainer-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # Linux-specific tools
    git
    curl
    wget
    bubblewrap
    socat
    strace
    tmux
    # Note: nodejs omitted - devcontainers typically provide their own version
  ];
  # Tmux config symlink
  home.file.".tmux.conf".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/tmux.conf";
  # Tmux helper scripts
  home.file.".local/bin/ta".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/ta";
  home.file.".local/bin/tmux-session-using-fzf".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/tmux-session-using-fzf";
  home.file.".local/bin/pane-nav".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/pane-nav";

  # ~/.ssh/rc keeps a stable agent socket symlink (~/.ssh/agent.sock) pointed at
  # the latest forwarded SSH_AUTH_SOCK so reconnecting ssh doesn't break agent
  # forwarding inside long-lived tmux sessions. tmux.conf consumes agent.sock.
  home.file.".ssh/rc".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/ssh-rc";


  # Install pkgx binary directly to ~/.local/bin (no sudo needed)
  home.activation.pkgxInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v pkgx &> /dev/null; then
      mkdir -p "$HOME/.local/bin"
      ${pkgs.curl}/bin/curl -o "$HOME/.local/bin/pkgx" --compressed --fail --proto '=https' "https://pkgx.sh/$(uname)/$(uname -m)"
      chmod 755 "$HOME/.local/bin/pkgx"
    fi
  '';

  # Override setupMagentaSkills from common.nix to also include the `search`
  # skill on Linux (macOS omits it).
  home.activation.setupMagentaSkills = lib.mkForce (lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.claude/skills"
    ${import ./magenta-skills.nix { inherit lib dotfilesDir; }}
  '');

  # Clone the personal benchling repo into ~/src and let its scripts/setup.sh
  # overlay the benchling-specific skill symlinks (atlassian, datadog, etc.) and
  # worktree context files on top of the nix-managed generic skills above.
  home.activation.cloneBenchling = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/src/benchling/.git" ]; then
      mkdir -p "$HOME/src"
      GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh" ${pkgs.git}/bin/git clone git@github.com:dlants/benchling.git "$HOME/src/benchling"
    fi
  '';

  home.activation.benchlingSetup = lib.hm.dag.entryAfter ["setupMagentaSkills" "cloneBenchling"] ''
    if [ -x "$HOME/src/benchling/scripts/setup.sh" ]; then
      ${pkgs.bash}/bin/bash "$HOME/src/benchling/scripts/setup.sh"
    fi
  '';


  # magenta.nvim's Linux sandbox uses strace, which needs ptrace to attach to
  # child processes. The devcontainer defaults to kernel.yama.ptrace_scope=2
  # (admin-only), so relax it to 1 (parent/child tracing) and persist it.
  home.activation.enablePtrace = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo 'kernel.yama.ptrace_scope = 1' | /usr/bin/sudo tee /etc/sysctl.d/10-ptrace.conf >/dev/null
    /usr/bin/sudo sysctl -w kernel.yama.ptrace_scope=1 >/dev/null
  '';

  # Set fish as login shell
  home.activation.setFishShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
    FISH_PATH="$HOME/.nix-profile/bin/fish"
    if [ -x "$FISH_PATH" ]; then
      if ! grep -qF "$FISH_PATH" /etc/shells 2>/dev/null; then
        echo "$FISH_PATH" | /usr/bin/sudo tee -a /etc/shells >/dev/null
      fi
      /usr/bin/sudo chsh -s "$FISH_PATH" "$USER"
    fi
  '';
  # Fish config (Linux-specific)
  xdg.configFile."fish/config.fish".source = lib.mkForce (config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/fish/config-linux.fish");
}
