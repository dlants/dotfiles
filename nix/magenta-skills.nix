# Shell snippet that symlinks magenta skills into ~/.claude/skills.
# Shared by common.nix and linux.nix (which overrides ordering) so the
# skill list lives in exactly one place.
{ lib, dotfilesDir }:
let
  skills = [ "browser" "plan" "search" "fetch" "code-review" ];
in
lib.concatMapStringsSep "\n" (s:
  ''ln -sfn "${dotfilesDir}/magenta-skills/${s}" "$HOME/.claude/skills/${s}"'') skills
