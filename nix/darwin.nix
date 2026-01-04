# macOS-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # macOS-specific tools (GUI apps installed via brew below)
  ];

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
