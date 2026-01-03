# Linux devcontainer-specific configuration
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Linux-specific tools
    git
    curl
    wget
  ];

  programs.fish.interactiveShellInit = ''
    # Linux-specific PATH additions
    set -gx PATH $PATH $HOME/.local/bin
  '';
}
