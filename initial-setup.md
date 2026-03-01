# dlants-dotfiles Setup Guide

## Current Installation Status

Your system has:
- **Nix**: ✅ Installed (multi-user daemon mode at `/nix`)
- **home-manager**: ✅ Installed and configured
- **fish shell**: ✅ Installed via nix at `~/.nix-profile/bin/fish`
- **nvim**: ✅ Configured with symlinks to this repo
- **Config files**: ✅ Symlinked to nix store

## Updates to System

- **Nix**: ✅ sourced within to ~/.zshrc -- to get lanuage servers working.
- Still using zsh for oh-my-zsh which has git plugin.
- [ ] I desire git shortcuts on fish, before switching to it.

### The Problem

Nix tools (including `fish`) are not in your current zsh PATH because the nix environment hasn't been sourced. You need to either:
1. Source nix in your current shell session, OR
2. Switch to fish shell (which has nix PATH configured)

## How This System Works

This is a **Nix + home-manager** based dotfiles setup:

1. **Nix** is a package manager that installs software in `/nix/store`
2. **home-manager** is a Nix tool that manages your user environment and dotfiles
3. **Flakes** (`flake.nix`) define reproducible configurations
4. Your configuration lives in `nix/common.nix` and `nix/darwin.nix`
5. Some config files (like `nvim/init.lua` and `fish/config-darwin.fish`) are **symlinked** from this repo to `~/.config/`, so you can edit them here and changes take effect immediately

### What Gets Installed

From `nix/common.nix`:
- Dev tools: ripgrep, fd, fzf, gh, rustup, tree-sitter
- Language servers: lua, typescript, bash, yaml, vscode-langservers
- Formatters: prettier, stylua
- Programs: fish, neovim, git

From `nix/darwin.nix` (macOS only):
- uv (Python package manager)
- tmux
- Homebrew apps: hammerspoon, pkgx

### Configuration Architecture

```
~/.config/nvim/ -> symlinks to /Users/mugabo/src/dlants-dotfiles/nvim/
~/.config/fish/ -> symlinks to nix store + this repo
~/.config/git/  -> managed by home-manager
~/.hammerspoon/ -> symlink to this repo
~/.tmux.conf    -> symlink to this repo
```

## Fresh Installation

If starting from scratch:

```bash
cd ~/src/dlants-dotfiles
./setup.sh
```

This will:
1. Install Nix (if not present)
2. Enable flakes in `~/.config/nix/nix.conf`
3. Run home-manager to:
   - Install all packages
   - Create config symlinks
   - Set up fish shell
   - Configure neovim

## Activating Your Environment (Current Situation)

You have everything installed but nix isn't in your PATH. To fix this:

### Option 1: Use fish shell (recommended)

```bash
# Start fish (it's at ~/.nix-profile/bin/fish)
~/.nix-profile/bin/fish

# Or add to your ~/.zshrc to make fish your default:
# fish
```

The fish config automatically adds nix to PATH (see `fish/config-darwin.fish:6-11`).

### Option 2: Source nix in zsh

Add to your `~/.zshrc`:
```bash
# Source nix
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
```

Then reload:
```bash
source ~/.zshrc
```

### Option 3: One-time activation

In your current shell:
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

This only lasts for the current session.

## Making Changes

### Updating Packages or Configuration

Edit `nix/common.nix` or `nix/darwin.nix`, then:

```bash
# Re-run home-manager
nix run home-manager/master -- switch --flake ~/src/dlants-dotfiles#macos -b backup
```

### Editing Config Files

Some files are "live" (not in nix store):
- `nvim/init.lua` - edit here, changes take effect immediately
- `nvim/lua/` - edit here, changes take effect immediately
- `fish/config-darwin.fish` - edit here, restart fish
- `tmux.conf` - edit here, reload tmux
- `hammerspoon/` - edit here, reload hammerspoon

After editing nix module files (`.nix` files), run home-manager switch.

## Troubleshooting

### "which nvim" shows nothing

Nix isn't in your PATH. See "Activating Your Environment" above.

### nvim is missing features

Check if language servers are installed:
```bash
which lua-language-server
which typescript-language-server
```

If missing, they're defined in `nix/common.nix:25-31`.

### Changes to nix files don't take effect

You need to run home-manager switch:
```bash
nix run home-manager/master -- switch --flake ~/src/dlants-dotfiles#macos -b backup
```

### fish config changes don't work

If you edited `fish/config-darwin.fish`:
1. The file is symlinked, so changes are immediate
2. Restart fish or run `source ~/.config/fish/config.fish`

If you edited `nix/common.nix` or `nix/darwin.nix`:
1. Run home-manager switch
2. Restart fish

## Rolling Back

### Remove everything and start fresh

```bash
# 1. Remove nix (this removes all nix-installed packages)
sudo rm -rf /nix
sudo rm -rf ~/.nix-profile
sudo rm -rf ~/.nix-defexpr
sudo rm -rf ~/.nix-channels
sudo rm -rf ~/.config/nix

# 2. Remove symlinks created by home-manager
rm -rf ~/.config/nvim
rm -rf ~/.config/fish
rm -rf ~/.config/git
rm -rf ~/.hammerspoon
rm ~/.tmux.conf

# 3. Clean up PATH changes
# Remove any nix-related lines from ~/.zshrc or ~/.bash_profile
```

### Undo just the home-manager configuration

```bash
# This will remove symlinks but keep nix installed
home-manager uninstall
```

### Restore a backup

home-manager creates backups with timestamp suffixes (like `.backup`):
```bash
# Find backups
ls -la ~/.config/nvim.backup* 2>/dev/null
ls -la ~/.config/fish.backup* 2>/dev/null

# Restore manually if needed
mv ~/.config/nvim ~/.config/nvim.nix-managed
mv ~/.config/nvim.backup ~/.config/nvim
```

## What You Need to Know

### Where are packages stored?

All nix packages are in `/nix/store/`. Each package has a unique hash.
Your profile (`~/.nix-profile/`) is a symlink pointing to a specific generation.

### How does PATH work?

- In fish: `fish/config-darwin.fish` adds `~/.nix-profile/bin` and `/nix/var/nix/profiles/default/bin` to PATH
- In zsh: You need to source the nix-daemon.sh script (see "Activating Your Environment")

### What if I want to use a different shell?

The setup works with any shell. Just make sure to source nix:
- zsh: source `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`
- bash: same as zsh
- fish: already configured in `fish/config-darwin.fish`

### Can I use this alongside Homebrew?

Yes! The fish config adds `/opt/homebrew/bin` to PATH (`fish/config-darwin.fish:13-16`).
The darwin config even installs some apps via Homebrew (`nix/darwin.nix:21-26`).

### What about VS Code / other editors?

Neovim is configured as the default editor (via `EDITOR` and `VISUAL` env vars).
But you can use any editor. Just be aware that language servers are installed via nix,
so they need to be in your PATH (which means sourcing nix).

## Next Steps

Based on your current state, I recommend:

1. **Immediate fix**: Start using fish shell:
   ```bash
   ~/.nix-profile/bin/fish
   ```

2. **Test nvim**: Open nvim and see what's working/broken:
   ```bash
   nvim
   ```

3. **Check what's missing**: In fish shell, verify:
   ```bash
   which lua-language-server
   which typescript-language-server
   ```

4. **Update if needed**: If packages are missing:
   ```bash
   nix run home-manager/master -- switch --flake ~/src/dlants-dotfiles#macos -b backup
   ```
