# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pathspec>=0.12",
#   "PyYAML>=6.0",
# ]
# ///
"""List the Copilot review instruction files that apply to a changeset.

Path-scoped instruction files (.github/instructions/*.instructions.md) are
selected the same way Copilot selects them: their frontmatter \`applyTo\` globs
are matched against the changed file paths. Repository-wide instructions
(.github/copilot-instructions.md) are always included.

Prints, one per line, the absolute path of each applicable instruction file.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import pathspec
import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("start", help="Starting git identifier (commit/branch/tag).")
    parser.add_argument(
        "stop",
        nargs="?",
        default=None,
        help=(
            "Ending git identifier. If omitted, the diff runs from <start> to the "
            "working tree and also includes staged, unstaged, and untracked files."
        ),
    )
    parser.add_argument(
        "--repo",
        default=".",
        help="Path to the git repository (default: current directory).",
    )
    return parser.parse_args()


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def changed_paths(repo: Path, start: str, stop: str | None) -> list[str]:
    paths: set[str] = set()
    if stop is not None:
        out = git(repo, "diff", "--name-only", f"{start}..{stop}")
        paths.update(line for line in out.splitlines() if line)
    else:
        out = git(repo, "diff", "--name-only", start)
        paths.update(line for line in out.splitlines() if line)
        out = git(repo, "ls-files", "--others", "--exclude-standard")
        paths.update(line for line in out.splitlines() if line)
    return sorted(paths)


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---"):
        return {}, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    try:
        meta = yaml.safe_load(parts[1]) or {}
    except yaml.YAMLError:
        meta = {}
    if not isinstance(meta, dict):
        meta = {}
    return meta, parts[2].lstrip("\n")


def normalize_globs(apply_to) -> list[str]:
    if apply_to is None:
        return []
    if isinstance(apply_to, str):
        return [apply_to]
    if isinstance(apply_to, list):
        return [str(g) for g in apply_to]
    return [str(apply_to)]


def matches(globs: list[str], paths: list[str]) -> bool:
    spec = pathspec.PathSpec.from_lines("gitwildmatch", globs)
    return any(spec.match_file(p) for p in paths)


def main() -> int:
    args = parse_args()
    repo = Path(args.repo).resolve()

    paths = changed_paths(repo, args.start, args.stop)
    if not paths:
        print("No changed files found for the given range.", file=sys.stderr)
        return 1

    instructions_dir = repo / ".github" / "instructions"
    repo_wide = repo / ".github" / "copilot-instructions.md"

    applicable: list[Path] = []

    if repo_wide.is_file():
        meta, _ = parse_frontmatter(repo_wide.read_text())
        if meta.get("excludeAgent") != "code-review":
            applicable.append(repo_wide)

    if instructions_dir.is_dir():
        for path in sorted(instructions_dir.glob("*.instructions.md")):
            meta, _ = parse_frontmatter(path.read_text())
            if meta.get("excludeAgent") == "code-review":
                continue
            globs = normalize_globs(meta.get("applyTo"))
            if not globs:
                continue
            if matches(globs, paths):
                applicable.append(path)

    for path in applicable:
        print(path.resolve())

    return 0


if __name__ == "__main__":
    sys.exit(main())
