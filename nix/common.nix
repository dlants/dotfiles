# Shared configuration for all platforms
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.stateVersion = "24.11";

  # Override tree-sitter to a newer version (nvim-treesitter main branch
  # requires tree-sitter-cli >= 0.26.1; nixpkgs still ships 0.25.x).
  nixpkgs.overlays = [
    (final: prev:
      let
        newSrc = prev.fetchFromGitHub {
          owner = "tree-sitter";
          repo = "tree-sitter";
          tag = "v0.26.8";
          hash = "sha256-fcFEfoALrbpBD6rWogxJ7FNVlvDQgswoX9ylRgko+8Q=";
          fetchSubmodules = true;
        };
      in {
        tree-sitter = prev.tree-sitter.overrideAttrs (old: {
          version = "0.26.8";
          src = newSrc;
          # buildRustPackage extracts cargoHash from its raw args (not finalAttrs),
          # so we must override cargoDeps directly to refetch against the new src.
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            src = newSrc;
            hash = "sha256-9FeWnWWPUWmMF15Psmul8GxGv2JceHWc2WZPmOr81gw=";
          };
          # Nixpkgs patches target 0.25.x source layout; skip them for 0.26.
          patches = [ ];
        });
      })
  ];

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
    jujutsu  # jj version control

    # Language servers
    lua-language-server
    typescript
    typescript-language-server
    bash-language-server
    yaml-language-server
    vscode-langservers-extracted
    terraform-ls
    tflint
    biome

    # Formatters
    prettier
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
  };

  # Starship prompt (supports git + jj via custom module)
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
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
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/starship.toml";
  };

  # Magenta skills symlinks (individual per skill, via activation so ordering works with linux clone)
  home.activation.setupMagentaSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.claude/skills"
    ln -sfn "${dotfilesDir}/magenta-skills/browser" "$HOME/.claude/skills/browser"
    ln -sfn "${dotfilesDir}/magenta-skills/plan" "$HOME/.claude/skills/plan"
  '';

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
