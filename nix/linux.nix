# Linux devcontainer-specific configuration
{ config, pkgs, lib, dotfilesDir, ... }:

{
  home.packages = with pkgs; [
    # Linux-specific tools
    git
    curl
    wget
    # Note: nodejs omitted - devcontainers typically provide their own version
  ];

  # Reminder script for ta (tmux lives on host, not in container)
  home.file.".local/bin/ta".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/ta-container-reminder";

  # Install pkgx binary directly to ~/.local/bin (no sudo needed)
  home.activation.pkgxInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ! command -v pkgx &> /dev/null; then
      mkdir -p "$HOME/.local/bin"
      ${pkgs.curl}/bin/curl -o "$HOME/.local/bin/pkgx" --compressed --fail --proto '=https' "https://pkgx.sh/$(uname)/$(uname -m)"
      chmod 755 "$HOME/.local/bin/pkgx"
    fi
  '';

  # Fish config (Linux-specific)
  xdg.configFile."fish/config.fish".source = lib.mkForce (config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/fish/config-linux.fish");
}
