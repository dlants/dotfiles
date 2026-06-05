import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Mirrors the SDK's JSONSchema/ThreadFn/LogFn shapes without importing the SDK,
// so this module stays dependency-free and unit-testable on its own.
export type ThreadFn = <T>(
  prompt: string,
  yieldSchema: unknown,
  options?: unknown,
) => Promise<T>;
export type LogFn = (message: string) => void;

export type CodeReviewParams = {
  start: string;
  stop?: string;
  repo?: string;
};

export type Finding = {
  file: string;
  line?: number;
  severity?: string;
  comment: string;
};

export type InstructionFile = {
  /** Path relative to the repo root, used as a stable label. */
  name: string;
  /** Full instruction prose (frontmatter stripped). */
  body: string;
};

export const CODE_REVIEW_PARAM_SCHEMA = {
  type: "object",
  properties: {
    start: {
      type: "string",
      description: "Git identifier (commit/branch/tag) to diff from.",
    },
    stop: {
      type: "string",
      description:
        "Optional ending git identifier. If omitted, diffs <start> against the working tree, including untracked files.",
    },
    repo: {
      type: "string",
      description: "Path to the git repository (defaults to the cwd).",
    },
  },
  required: ["start"],
} as const;

export const FINDINGS_YIELD_SCHEMA = {
  type: "object",
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          file: { type: "string" },
          line: { type: "number" },
          severity: {
            type: "string",
            description: "e.g. blocker, warning, nit",
          },
          comment: { type: "string" },
        },
        required: ["file", "comment"],
      },
    },
  },
  required: ["findings"],
} as const;

function git(repo: string, ...args: string[]): string {
  return execFileSync("git", ["-C", repo, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
}

/**
 * Compute the set of changed file paths for the requested range. With a `stop`
 * ref, this is a plain `start..stop` diff; without it, the diff runs from
 * `start` to the working tree and also folds in untracked files — matching the
 * Copilot code-review selection behavior.
 */
export function getChangedPaths(
  repo: string,
  start: string,
  stop?: string,
): string[] {
  const paths = new Set<string>();
  if (stop) {
    for (const line of git(repo, "diff", "--name-only", `${start}..${stop}`)
      .split("\n")
      .filter(Boolean)) {
      paths.add(line);
    }
  } else {
    for (const line of git(repo, "diff", "--name-only", start)
      .split("\n")
      .filter(Boolean)) {
      paths.add(line);
    }
    for (const line of git(repo, "ls-files", "--others", "--exclude-standard")
      .split("\n")
      .filter(Boolean)) {
      paths.add(line);
    }
  }
  return [...paths].sort();
}

/** Split a frontmatter block into its parsed keys and the remaining body. */
export function parseFrontmatter(text: string): {
  meta: Record<string, string | string[]>;
  body: string;
} {
  if (!text.startsWith("---")) return { meta: {}, body: text };
  const parts = text.split(/^---\s*$/m);
  // parts[0] is "" (before first ---), parts[1] is the frontmatter, parts[2..] body.
  if (parts.length < 3) return { meta: {}, body: text };
  const meta: Record<string, string | string[]> = {};
  for (const raw of parts[1].split("\n")) {
    const line = raw.trim();
    const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!m) continue;
    const key = m[1];
    let value = m[2].trim();
    if (value.startsWith("[") && value.endsWith("]")) {
      meta[key] = value
        .slice(1, -1)
        .split(",")
        .map((s) => stripQuotes(s.trim()))
        .filter(Boolean);
    } else {
      meta[key] = stripQuotes(value);
    }
  }
  return { meta, body: parts.slice(2).join("---").replace(/^\n+/, "") };
}

function stripQuotes(s: string): string {
  if (
    (s.startsWith('"') && s.endsWith('"')) ||
    (s.startsWith("'") && s.endsWith("'"))
  ) {
    return s.slice(1, -1);
  }
  return s;
}

function normalizeGlobs(applyTo: string | string[] | undefined): string[] {
  if (applyTo === undefined) return [];
  const list = Array.isArray(applyTo) ? applyTo : applyTo.split(",");
  return list.map((g) => g.trim()).filter(Boolean);
}

/** Convert a gitignore-style glob into an anchored RegExp. */
export function globToRegExp(glob: string): RegExp {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        // ** — any number of path segments
        i++;
        if (glob[i + 1] === "/") {
          i++;
          re += "(?:.*/)?";
        } else {
          re += ".*";
        }
      } else {
        re += "[^/]*";
      }
    } else if (c === "?") {
      re += "[^/]";
    } else if (c === "{") {
      re += "(?:";
    } else if (c === "}") {
      re += ")";
    } else if (c === ",") {
      re += "|";
    } else if (".+^$()|[]\\".includes(c)) {
      re += `\\${c}`;
    } else {
      re += c;
    }
  }
  return new RegExp(`^${re}$`);
}

export function globsMatch(globs: string[], paths: string[]): boolean {
  const regexes = globs.map(globToRegExp);
  return paths.some((p) => regexes.some((r) => r.test(p)));
}

/**
 * Select the instruction files that apply to the changed paths. Path-scoped
 * files in `.github/instructions/*.instructions.md` are matched by their
 * `applyTo` globs; the repository-wide `.github/copilot-instructions.md` is
 * always included. Files marked `excludeAgent: code-review` are skipped.
 */
export function discoverApplicableInstructions(
  repo: string,
  changedFiles: string[],
): InstructionFile[] {
  const applicable: InstructionFile[] = [];

  const repoWide = path.join(repo, ".github", "copilot-instructions.md");
  if (existsSync(repoWide)) {
    const { meta, body } = parseFrontmatter(readFileSync(repoWide, "utf8"));
    if (meta.excludeAgent !== "code-review") {
      applicable.push({ name: ".github/copilot-instructions.md", body });
    }
  }

  const instructionsDir = path.join(repo, ".github", "instructions");
  if (existsSync(instructionsDir)) {
    const files = readdirSync(instructionsDir)
      .filter((f) => f.endsWith(".instructions.md"))
      .sort();
    for (const f of files) {
      const { meta, body } = parseFrontmatter(
        readFileSync(path.join(instructionsDir, f), "utf8"),
      );
      if (meta.excludeAgent === "code-review") continue;
      const globs = normalizeGlobs(meta.applyTo);
      if (globs.length === 0) continue;
      if (globsMatch(globs, changedFiles)) {
        applicable.push({ name: `.github/instructions/${f}`, body });
      }
    }
  }

  return applicable;
}

/** Build the per-instruction review prompt handed to a spawned thread. */
export function buildReviewPrompt(
  instruction: InstructionFile,
  params: CodeReviewParams,
): string {
  const diffCmd = params.stop
    ? `git diff ${params.start}..${params.stop}`
    : `git diff ${params.start}`;
  const repoLine = params.repo ? `\nRepository: ${params.repo}` : "";
  return [
    `You are reviewing a changeset strictly from the perspective of one instruction file: ${instruction.name}.`,
    repoLine,
    "",
    "Review the actual diff produced by:",
    `  ${diffCmd}`,
    params.stop
      ? ""
      : "  (also consider staged, unstaged, and untracked files)",
    "",
    "Apply ONLY the following guidelines. Do not restate them. Report concrete,",
    "actionable findings with file and line references. If nothing applies, return",
    "an empty findings list.",
    "",
    "--- BEGIN GUIDELINES ---",
    instruction.body.trim(),
    "--- END GUIDELINES ---",
    "",
    "When done, yield_to_parent with the structured findings.",
  ].join("\n");
}

/**
 * Orchestrate a code review: discover the applicable instruction files, spawn
 * one review thread per file (in parallel), and aggregate their findings.
 * Returns the findings grouped by instruction file.
 */
export async function runReview({
  params,
  thread,
  log,
}: {
  params: CodeReviewParams;
  thread: ThreadFn;
  log: LogFn;
}): Promise<{ instruction: string; findings: Finding[] }[]> {
  const repo = params.repo ?? process.cwd();

  const changed = getChangedPaths(repo, params.start, params.stop);
  if (changed.length === 0) {
    log("No changed files found for the given range.");
    return [];
  }
  log(`Reviewing ${changed.length} changed file(s).`);

  const instructions = discoverApplicableInstructions(repo, changed);
  if (instructions.length === 0) {
    log("No applicable instruction files for the changeset.");
    return [];
  }
  log(
    `Spawning ${instructions.length} review thread(s): ${instructions
      .map((i) => i.name)
      .join(", ")}`,
  );

  const results = await Promise.all(
    instructions.map(async (instruction) => {
      const { findings } = await thread<{ findings: Finding[] }>(
        buildReviewPrompt(instruction, params),
        FINDINGS_YIELD_SCHEMA,
      );
      log(`${instruction.name}: ${findings.length} finding(s).`);
      return { instruction: instruction.name, findings };
    }),
  );

  const total = results.reduce((n, r) => n + r.findings.length, 0);
  log(`Code review complete: ${total} finding(s) across all guidelines.`);
  return results;
}
