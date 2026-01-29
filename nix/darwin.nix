# macOS-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # macOS-specific tools (GUI apps installed via brew below)
    uv  # For installing ty (Python type checker not yet in nixpkgs)
    nodejs  # includes npm
    tmux
  ];

  # Tmux config symlink
  home.file.".tmux.conf".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/tmux.conf";

  # Tmux helper scripts
  home.file.".local/bin/ta".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/ta";
  home.file.".local/bin/tmux-session-using-fzf".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/tmux-session-using-fzf";
  home.file.".local/bin/clipboard-sync".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/clipboard-sync";

  # Install apps via Homebrew (not available in nixpkgs for macOS)
  home.activation.brewInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v brew &> /dev/null; then
      brew list --cask hammerspoon &> /dev/null || brew install --cask hammerspoon
      brew list pkgx &> /dev/null || brew install pkgx
    fi
  '';

  # Hammerspoon config (macOS-only, uses ~/.hammerspoon not XDG)
  home.file.".hammerspoon".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/hammerspoon";

  # Fish config (macOS-specific)
  xdg.configFile."fish/config.fish".source = lib.mkForce (config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/fish/config-darwin.fish");
}
