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
    nodejs # includes npm

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

    # For installing ty (Python type checker not yet in nixpkgs)
    uv
  ];

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      alias = {
        co = "checkout";
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
    ];
  };

  # Symlink configs (live-linked, not copied to nix store)
  xdg.configFile = {
    "nvim/init.lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/nvim/init.lua";
    "nvim/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/nvim/lua";
  };

  # Magenta skills symlinks (individual per skill)
  home.file.".magenta/skills/browser".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/magenta-skills/browser";

  # Prevent rustup from creating a broken fish config (nix manages PATH)
  home.file.".config/fish/conf.d/rustup.fish".text = "";

  # Clone magenta.nvim if it doesn't exist
  home.activation.cloneMagenta = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/src/magenta.nvim" ]; then
      mkdir -p "$HOME/src"
      ${pkgs.git}/bin/git clone https://github.com/dlants/magenta.nvim.git "$HOME/src/magenta.nvim"
    fi
  '';

  # Install ty via uv (Rust binary on PyPI, not yet in nixpkgs)
  home.activation.installTy = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.uv}/bin/uv tool install ty 2>/dev/null || true
  '';
}
