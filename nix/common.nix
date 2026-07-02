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
        # Pin tmux to 3.6b: nixpkgs' 3.7 and our previous 3.7a pin both have a
        # rendering regression that corrupts nvim's display inside tmux (garbled
        # text, broken pane borders) on macOS + Ghostty. Bisected by ruling out
        # zsh, Ghostty shell-integration, and tmux.conf first; confirmed fixed
        # on 3.6b. Try bumping to 3.7b+ periodically to see if it's fixed
        # upstream, then drop this override.
        tmux = prev.tmux.overrideAttrs (old: {
          version = "3.6b";
          src = prev.fetchFromGitHub {
            owner = "tmux";
            repo = "tmux";
            tag = "3.6b";
            hash = "sha256-iW4K/OxSVpxVkyI5Dy6lzwVf/8nXyjcHtL76Ezmxavc=";
          };
        });

        tree-sitter = prev.tree-sitter.overrideAttrs (old: {
          version = "0.26.8";
          src = newSrc;
          # buildRustPackage extracts cargoHash from its raw args (not finalAttrs),
          # so we must override cargoDeps directly to refetch against the new src.
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            src = newSrc;
            hash = "sha256-9FeWnWWPUWmMF15Psmul8GxGv2JceHWc2WZPmOr81gw=";
          };
          # tree-sitter 0.26 pulls in rquickjs-sys, which uses bindgen and needs libclang.
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ prev.rustPlatform.bindgenHook ];
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
    gopls  # Go language server

    # Go toolchain & tools
    go
    delve  # Go debugger (dlv)

    # Formatters
    carapace
    prettier
    stylua
    gofumpt   # stricter gofmt
    (lib.lowPrio gotools)  # goimports (lowPrio: avoids `modernize` clash with gopls)
    golangci-lint  # Go meta-linter
  ];

  # Git configuration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      alias = {
        co = "checkout";
      };
      push = {
        autoSetupRemote = true;
      };
    };
  };

  # Zsh shell. Configured entirely via nix, no oh-my-zsh.
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # The Nix installer normally wires PATH setup into /etc/zshrc or a
    # nix-daemon.sh profile script, but neither exists on this machine (the
    # devcontainer has no /nix/var/nix/profiles/default/etc/profile.d at
    # all), so zsh never saw the nix/home-manager profile bin dirs on PATH.
    # Prepend them ourselves, as early as possible (.zshenv).
    envExtra = ''
      export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
    '';

    history = {
      size = 100000;
      save = 100000;
      share = true;
      extended = true;
      ignoreDups = true;
    };

    plugins = lib.optionals pkgs.stdenv.isDarwin [
      # fzf-tab ships a compiled module (fzftab.so) that dlopen()s against the
      # *system* libc rather than nix's own glibc. On the Ubuntu 22.04
      # devcontainer (glibc 2.35) that .so was built against a newer glibc
      # (2.38+), so it fails to load and spams errors on every zsh startup.
      # macOS doesn't hit this since there's no glibc there.
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ] ++ [
      {
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
        file = "share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh";
      }
      {
        name = "zsh-vi-mode";
        src = pkgs.zsh-vi-mode;
        file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
      }
    ];

    initContent = ''
      export CARAPACE_BRIDGES='zsh,bash'
      zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
      source <(carapace _carapace)

      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      if [ -f ~/.config/zsh/config-platform.zsh ]; then
        source ~/.config/zsh/config-platform.zsh
      fi
    '';
  };

  # Starship prompt (supports git + jj via custom module)
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
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

  # Symlink magenta context file
  home.file.".magenta/context.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/magenta-context.md";

  # Symlink the magenta scripts directory to ~/.magenta/scripts. Magenta scans
  # each package subdirectory (e.g. magenta-scripts/dotfiles) for an index.ts.
  home.file.".magenta/scripts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/magenta-scripts";

  # Each script package imports the SDK via a `magenta-sdk` symlink that magenta
  # does not manage for us. magenta lives either in the local checkout (macOS) or
  # in the neovim pack dir (Linux), so point the symlink at whichever exists.
  home.activation.linkMagentaSdk = lib.hm.dag.entryAfter ["cloneMagenta"] ''
    sdk=""
    for candidate in \
      "$HOME/src/magenta.nvim/sdk" \
      "$HOME/.local/share/nvim/site/pack/core/opt/magenta/sdk"; do
      if [ -d "$candidate" ]; then sdk="$candidate"; break; fi
    done
    if [ -n "$sdk" ]; then
      for pkg in "${dotfilesDir}/magenta-scripts"/*/; do
        [ -f "$pkg/index.ts" ] || continue
        ln -sfn "$sdk" "$pkg/magenta-sdk"
      done
    fi
  '';

  # Install each script package's runtime deps (e.g. zx). node_modules is
  # gitignored, so the forked script can only resolve them once installed.
  home.activation.installMagentaScriptDeps = lib.hm.dag.entryAfter ["linkMagentaSdk"] ''
    if command -v npm > /dev/null; then
      for pkg in "${dotfilesDir}/magenta-scripts"/*/; do
        [ -f "$pkg/package.json" ] || continue
        ( cd "$pkg" && npm install --omit=dev --no-audit --no-fund ) || true
      done
    fi
  '';

  # Install the pkb CLI to ~/go/bin, always tracking latest on each activation.
  # Impure (needs network + go), so failures are non-fatal. Ensure ~/go/bin is on PATH.
  home.activation.installPkb = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v go > /dev/null; then
      PATH="${pkgs.go}/bin:$PATH" GOBIN="$HOME/go/bin" \
        ${pkgs.go}/bin/go install github.com/dlants/pkb@latest || true
    fi
  '';

  # Magenta skills symlinks (skill list defined in ./magenta-skills.nix)
  home.activation.setupMagentaSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.claude/skills"
    ${import ./magenta-skills.nix { inherit lib dotfilesDir; includeSearch = false; }}
  '';


  # Clone locally-authored neovim plugins into ~/src if they don't exist. On
  # macOS these are loaded from ~/src (see nvim/lua/config/pack.lua) so local
  # edits take effect immediately; on Linux pack.lua fetches them via vim.pack.
  home.activation.cloneLocalPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/src"
    for repo in magenta.nvim needle shuck glean; do
      if [ ! -d "$HOME/src/$repo" ]; then
        ${pkgs.git}/bin/git clone "https://github.com/dlants/$repo.git" "$HOME/src/$repo"
      fi
    done
  '';
}
