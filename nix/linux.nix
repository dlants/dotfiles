# Linux devcontainer-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # Linux-specific tools
    git
    curl
    wget
  ];

  # Fish config (Linux-specific)
  xdg.configFile."fish/config.fish".source = lib.mkForce (config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/fish/config-linux.fish");
}
