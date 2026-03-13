# Linux devcontainer-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # Linux-specific tools
    git
    curl
    wget
    # Note: nodejs omitted - devcontainers typically provide their own version
  ];

  # Reminder script for ta (tmux lives on host, not in container)
  home.file.".local/bin/ta".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/ta-container-reminder";

  # Install pkgx binary directly to ~/.local/bin (no sudo needed)
  home.activation.pkgxInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v pkgx &> /dev/null; then
      mkdir -p "$HOME/.local/bin"
      ${pkgs.curl}/bin/curl -o "$HOME/.local/bin/pkgx" --compressed --fail --proto '=https' "https://pkgx.sh/$(uname)/$(uname -m)"
      chmod 755 "$HOME/.local/bin/pkgx"
    fi
  '';

  # Clone work-skills into ~/.claude/skills (browser skill symlink added after by setupMagentaSkills)
  home.activation.cloneWorkSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/.claude/skills" ]; then
      mkdir -p "$HOME/.claude"
      GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh" ${pkgs.git}/bin/git clone git@github.com:benchling/work-skills.git "$HOME/.claude/skills"
    fi
  '';

  # Override setupMagentaSkills from common.nix to run after cloneWorkSkills
  home.activation.setupMagentaSkills = lib.mkForce (lib.hm.dag.entryAfter ["writeBoundary" "cloneWorkSkills"] ''
    mkdir -p "$HOME/.claude/skills"
    ln -sfn "${dotfilesDir}/magenta-skills/browser" "$HOME/.claude/skills/browser"
  '');

  # Clone dlants-pkb as ~/pkb
  home.activation.clonePkb = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/pkb" ]; then
      GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh" ${pkgs.git}/bin/git clone git@github.com:benchling/dlants-pkb.git "$HOME/pkb"
    fi
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
