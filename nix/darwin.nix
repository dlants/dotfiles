# macOS-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # macOS-specific tools (GUI apps installed via brew below)
  ];

  # Install GUI apps via Homebrew (not available in nixpkgs for macOS)
  home.activation.brewCasks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v brew &> /dev/null; then
      brew list --cask hammerspoon &> /dev/null || brew install --cask hammerspoon
    fi
  '';

  # Hammerspoon config (macOS-only, uses ~/.hammerspoon not XDG)
  home.file.".hammerspoon".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/hammerspoon";

  programs.fish.interactiveShellInit = ''
    # OrbStack integration
    source ~/.orbstack/shell/init2.fish 2>/dev/null || true

    # macOS-specific PATH additions
    set -gx PATH $PATH /Users/denis.lantsman/.local/bin
    set -gx DISPLAY :0
  '';

  # macOS-specific settings
  programs.neovim.extraConfig = ''
    vim.o.shell = "/opt/homebrew/bin/zsh"
  '';
}
