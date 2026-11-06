# Shell snippet that symlinks magenta skills into ~/.claude/skills.
# Shared by common.nix and linux.nix (which overrides ordering) so the
# skill list lives in exactly one place.
{ lib, dotfilesDir, platform, includeSearch ? true, gleanSkillsDir ? "$HOME/src/glean/skills/glean-review" }:
let
  skills = [ "browser" "fetch" "review" "magenta-archive" "wait-pr" ]
    ++ lib.optional includeSearch "search";
  # Skills that live in their own project repo; symlinked from there so the
  # skill ships with the code it documents.
  externalSkills = { glean-review = gleanSkillsDir; };
  link = src: name: ''ln -sfn "${src}" "$HOME/.claude/skills/${name}"'';
  # Skills with per-platform variants live in `<name>-<platform>` dirs.
  platformSkills = [ "plan" ];
in
lib.concatStringsSep "\n" (
  map (s: link "${dotfilesDir}/magenta-skills/${s}" s) skills
  ++ map (s: link "${dotfilesDir}/magenta-skills/${s}-${platform}" s) platformSkills
  ++ lib.mapAttrsToList (name: src: link src name) externalSkills
)
