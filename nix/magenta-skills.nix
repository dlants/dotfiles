# Shell snippet that symlinks magenta skills into ~/.claude/skills.
# Shared by common.nix and linux.nix (which overrides ordering) so the
# skill list lives in exactly one place.
{ lib, dotfilesDir, includeSearch ? true }:
let
  skills = [ "browser" "plan" "fetch" ]
    ++ lib.optional includeSearch "search";
  # Skills that live in their own project repo; symlinked from there so the
  # skill ships with the code it documents.
  externalSkills = { glean-review = "$HOME/src/glean/skills/glean-review"; };
  link = src: name: ''ln -sfn "${src}" "$HOME/.claude/skills/${name}"'';
in
lib.concatStringsSep "\n" (
  map (s: link "${dotfilesDir}/magenta-skills/${s}" s) skills
  ++ lib.mapAttrsToList (name: src: link src name) externalSkills
)
