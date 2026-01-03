# Shared configuration for all platforms
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  # Enable flakes
  home.file.".config/nix/nix.conf".text = ''
    experimental-features = nix-command flakes
  '';

  # Common packages
  home.packages = with pkgs; [
    # Dev tools
    ripgrep
    fd
    fzf
    delta  # git-delta
    gh     # GitHub CLI

    # Language servers
    lua-language-server
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.bash-language-server
    nodePackages.yaml-language-server
    nodePackages.vscode-langservers-extracted

    # Formatters
    nodePackages.prettier
    stylua
  ];

  # Fish shell
  programs.fish.enable = true;

  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    extraPackages = with pkgs; [
      ripgrep
      fd
      nodejs
    ];
  };

  # Symlink configs (live-linked, not copied to nix store)
  xdg.configFile = {
    "nvim/init.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/nvim/init.lua";
    "nvim/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/nvim/lua";
  };
}
