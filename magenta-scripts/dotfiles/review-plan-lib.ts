import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import type { LogFn, ThreadFn } from "./magenta-sdk/index.ts";

export type ReviewPlanParams = {
  /** Path to the plan file (absolute, or relative to the repo root). */
  plan: string;
  /**
   * Absolute path to the repository the plan targets. Required: the forked
   * script process's cwd is magenta's install directory, not the project.
   */
  repo: string;
  /** Directory of perspective markdown files (absolute, or relative to the repo root). */
  instructions: string;
};

export type PlanFinding = {
  section?: string;
  severity?: string;
  comment: string;
};

export type Perspective = { name: string; body: string };

export type PerspectiveFindings = {
  perspective: string;
  findings: PlanFinding[];
};

export const REVIEW_PLAN_PARAM_SCHEMA = {
  type: "object",
  properties: {
    plan: {
      type: "string",
      description: "Path to the plan file (absolute or relative to the repo).",
    },
    repo: {
      type: "string",
      description: "Absolute path to the repository the plan targets.",
    },
    instructions: {
      type: "string",
      description:
        "Directory of review perspective markdown files, one review thread per file (absolute or relative to the repo).",
    },
  },
  required: ["plan", "repo", "instructions"],
} as const;

export const PLAN_FINDINGS_YIELD_SCHEMA = {
  type: "object",
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          section: {
            type: "string",
            description: "Plan section or stage the finding refers to.",
          },
          severity: {
            type: "string",
            description: "e.g. blocker, warning, nit",
          },
          comment: { type: "string" },
        },
        required: ["comment"],
      },
    },
  },
  required: ["findings"],
} as const;

export const ADDRESS_YIELD_SCHEMA = {
  type: "object",
  properties: {
    summary: {
      type: "string",
      description: "What was changed in the plan, and which findings were rejected and why.",
    },
  },
  required: ["summary"],
} as const;

export function loadPerspectives(dir: string): Perspective[] {
  return readdirSync(dir)
    .filter((f) => f.endsWith(".md"))
    .sort()
    .map((f) => ({
      name: f.replace(/\.md$/, ""),
      body: readFileSync(path.join(dir, f), "utf8").trim(),
    }));
}

/**
 * Everything up to the perspective is identical across review threads, so the
 * provider can reuse the cached prefix. Keep all per-perspective text after it.
 */
export function buildReviewPrefix(
  planLabel: string,
  planBody: string,
  repo: string,
): string {
  return [
    "You are reviewing an implementation plan before any code is written.",
    `Repository: ${repo}`,
    `Plan file: ${planLabel}`,
    "",
    "Read the relevant parts of the repository as needed to ground your review in the actual code. Do not modify any files.",
    "Report concrete, actionable findings, each referencing the plan section or stage it concerns. Do not restate the guidelines. If nothing applies, return an empty findings list. When done, yield_to_parent with the structured findings.",
    "",
    "--- BEGIN PLAN ---",
    planBody.trim(),
    "--- END PLAN ---",
    "",
    "Review the plan strictly from the following perspective:",
    "",
  ].join("\n");
}

export function buildReviewPrompt(prefix: string, perspective: Perspective): string {
  return `${prefix}--- BEGIN PERSPECTIVE: ${perspective.name} ---\n${perspective.body}\n--- END PERSPECTIVE ---\n`;
}

export function formatPlanFindings(results: PerspectiveFindings[]): string {
  const lines: string[] = [];
  for (const { perspective, findings } of results) {
    if (findings.length === 0) continue;
    lines.push(`### ${perspective}`);
    for (const f of findings) {
      const sev = f.severity ? `[${f.severity}] ` : "";
      const loc = f.section ? `${f.section} — ` : "";
      lines.push(`- ${sev}${loc}${f.comment}`);
    }
    lines.push("");
  }
  return lines.join("\n").trim();
}

export function buildAddressPrompt(
  planLabel: string,
  results: PerspectiveFindings[],
): string {
  return [
    `A review of the plan ${planLabel} produced the findings below. Revise the plan file to address them.`,
    "",
    formatPlanFindings(results),
    "",
    "Instructions:",
    "- Work autonomously: do not ask for confirmation.",
    "- Only edit the plan file. Do not change any code.",
    "- Verify each finding against the repository before acting on it. Reject findings that are wrong or would make the plan worse.",
    "- Keep the plan concise; integrate changes into the existing structure rather than appending a review log.",
    "",
    "When done, yield_to_parent with a summary of the changes and of any rejected findings with reasons.",
  ].join("\n");
}

export async function runReviewPlan({
  params,
  thread,
  log,
}: {
  params: ReviewPlanParams;
  thread: ThreadFn;
  log: LogFn;
}): Promise<{ results: PerspectiveFindings[]; summary?: string }> {
  const { repo } = params;
  const planAbs = path.isAbsolute(params.plan)
    ? params.plan
    : path.join(repo, params.plan);
  if (!existsSync(planAbs)) throw new Error(`Plan file not found: ${planAbs}`);
  const planLabel = path.relative(repo, planAbs);
  const instructionsAbs = path.resolve(repo, params.instructions);
  if (!existsSync(instructionsAbs)) {
    throw new Error(`Instructions directory not found: ${instructionsAbs}`);
  }
  const perspectives = loadPerspectives(instructionsAbs);
  if (perspectives.length === 0) {
    throw new Error(`No .md perspective files in ${instructionsAbs}`);
  }
  const prefix = buildReviewPrefix(planLabel, readFileSync(planAbs, "utf8"), repo);

  log(`Spawning ${perspectives.length} review thread(s): ${perspectives.map((p) => p.name).join(", ")}`);
  const results = await Promise.all(
    perspectives.map(async (perspective) => {
      const { findings } = await thread<{ findings: PlanFinding[] }>(
        buildReviewPrompt(prefix, perspective),
        PLAN_FINDINGS_YIELD_SCHEMA,
        { cwd: repo },
      );
      log(`${perspective.name}: ${findings.length} finding(s).`);
      return { perspective: perspective.name, findings };
    }),
  );

  const total = results.reduce((n, r) => n + r.findings.length, 0);
  if (total === 0) {
    log("Plan review clean.");
    return { results };
  }
  log(`Addressing ${total} finding(s).`);
  const { summary } = await thread<{ summary: string }>(
    buildAddressPrompt(planLabel, results),
    ADDRESS_YIELD_SCHEMA,
    { cwd: repo, contextFiles: [planAbs] },
  );
  log(summary);
  return { results, summary };
}
