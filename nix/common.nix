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
    rustup
    tree-sitter

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

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      alias = {
        co = "checkout";
      };
      push = {
        autoSetupRemote = true;
      };
    };
  };

  # Fish shell
  programs.fish = {
    enable = true;
    plugins = [
      {
        name = "pure";
        src = pkgs.fishPlugins.pure.src;
      }
    ];
  };

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
      tree-sitter
    ];
  };

  # Symlink configs (live-linked, not copied to nix store)
  xdg.configFile = {
    "nvim/init.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/nvim/init.lua";
    "nvim/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/nvim/lua";
  };

  # Magenta skills symlinks (individual per skill)
  home.file.".claude/skills/browser".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/magenta-skills/browser";

  # Prevent rustup from creating a broken fish config (nix manages PATH)
  home.file.".config/fish/conf.d/rustup.fish".text = "";

  # Clone magenta.nvim if it doesn't exist
  home.activation.cloneMagenta = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/src/magenta.nvim" ]; then
      mkdir -p "$HOME/src"
      ${pkgs.git}/bin/git clone https://github.com/dlants/magenta.nvim.git "$HOME/src/magenta.nvim"
    fi
  '';

  # Install ty via uv if not already available (uv may be system-provided on Linux)
  home.activation.installTy = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v ty &> /dev/null; then
      if command -v uv &> /dev/null; then
        uv tool install ty 2>/dev/null || true
      fi
    fi
  '';
}
