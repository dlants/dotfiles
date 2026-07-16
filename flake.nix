{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # Pinned separately so `nix flake update` of the main nixpkgs never drags
    # starship into a local source build (darwin binaries lag the channel).
    # Bump this rev manually to move starship; verify the new rev's starship is
    # cached for aarch64-darwin before switching.
    nixpkgs-starship.url = "github:nixos/nixpkgs/b86751bc4085f48661017fa226dee99fab6c651b";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nixpkgs-starship, ... }:
    let
      mkHomeConfig = { system, username, homeDirectory, dotfilesDir, extraModules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit dotfilesDir;
            starshipPkg = nixpkgs-starship.legacyPackages.${system}.starship;
          };
          modules = [
            ./nix/common.nix
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ] ++ extraModules;
        };
    in {
      homeConfigurations = {
        # macOS laptop
        "macos" = mkHomeConfig {
          system = "aarch64-darwin";
          username = "denis.lantsman";
          homeDirectory = "/Users/denis.lantsman";
          dotfilesDir = "/Users/denis.lantsman/src/dotfiles";
          extraModules = [ ./nix/darwin.nix ];
        };

        # Ubuntu devcontainer
        "devcontainer" = mkHomeConfig {
          system = "aarch64-linux";
          username = "aurelia";
          homeDirectory = "/home/aurelia";
          dotfilesDir = "/home/aurelia/src/dotfiles";
          extraModules = [ ./nix/linux.nix ];
        };
      };
    };
}
