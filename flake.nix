{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      mkHomeConfig = { system, username, homeDirectory, dotfilesDir, extraModules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit dotfilesDir; };
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
