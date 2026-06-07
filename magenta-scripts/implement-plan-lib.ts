import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import {
  type Finding,
  getChangedPaths,
  type LogFn,
  runReview,
  type ThreadFn,
} from "./code-review-lib.ts";

export type ImplementPlanParams = {
  /** Path to the plan file (absolute, or relative to the repo root). */
  plan: string;
  /** Path to the git repository (defaults to the cwd). */
  repo?: string;
  /** Branch to create for the implementation (defaults to a generated name). */
  branch?: string;
};

export type Stage = {
  title: string;
  summary: string;
};

/** Max review<->address cycles per stage before committing regardless. */
export const MAX_REVIEW_ROUNDS = 3;

/** Recurring reminder injected into implement/address threads. */
export const PLAN_MAINTENANCE_REMINDER =
  "You are implementing a plan stage by stage. Keep the plan file updated as you " +
  "work: record progress as items are completed, and note any decisions or " +
  "deviations so the plan stays an accurate reflection of the work.";

export const IMPLEMENT_PLAN_PARAM_SCHEMA = {
  type: "object",
  properties: {
    plan: {
      type: "string",
      description: "Path to the plan file (absolute or relative to the repo).",
    },
    repo: {
      type: "string",
      description: "Path to the git repository (defaults to the cwd).",
    },
    branch: {
      type: "string",
      description:
        "Branch to create for the implementation. Defaults to a generated name.",
    },
  },
  required: ["plan"],
} as const;

export const STAGES_YIELD_SCHEMA = {
  type: "object",
  properties: {
    stages: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          summary: {
            type: "string",
            description: "One or two sentences describing the stage's scope.",
          },
        },
        required: ["title", "summary"],
      },
    },
  },
  required: ["stages"],
} as const;

export const STAGE_DONE_YIELD_SCHEMA = {
  type: "object",
  properties: {
    done: { type: "boolean" },
    notes: {
      type: "string",
      description: "Short summary of what was done or changed.",
    },
  },
  required: ["done"],
} as const;

function git(repo: string, ...args: string[]): string {
  return execFileSync("git", ["-C", repo, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
}

export function defaultBranchName(planPath: string): string {
  const base = path
    .basename(planPath)
    .replace(/\.[^.]+$/, "")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  const stamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14);
  return `implement/${base || "plan"}-${stamp}`;
}

export function buildExtractStagesPrompt(
  planPath: string,
  planBody: string,
): string {
  return [
    "Break the following implementation plan into its ordered, independently",
    "committable stages. Preserve the plan author's own staging if the plan",
    "already defines stages; otherwise infer a small number of coherent stages.",
    "",
    `Plan file: ${planPath}`,
    "",
    "--- BEGIN PLAN ---",
    planBody.trim(),
    "--- END PLAN ---",
    "",
    "Do not implement anything. When done, yield_to_parent with the ordered list",
    "of stages, each with a short title and a one- or two-sentence summary.",
  ].join("\n");
}

export function buildImplementStagePrompt(
  stage: Stage,
  index: number,
  total: number,
  planPath: string,
): string {
  return [
    `You are implementing ONE stage of a ${total}-stage implementation plan.`,
    "",
    `Plan file: ${planPath}`,
    "Read the full plan before starting so you understand the surrounding context.",
    "",
    `## Stage ${index}/${total}: ${stage.title}`,
    stage.summary,
    "",
    "Instructions:",
    "- Implement ONLY this stage. Do not begin work that belongs to later stages.",
    "- Work until this stage is fully complete, including tests where appropriate.",
    `- Document your progress directly in the plan file (${planPath}): check off`,
    "  completed items and add brief progress notes under this stage.",
    `- If you deviate from the plan, update the plan file (${planPath}) so it`,
    "  reflects what you actually did.",
    "- Do NOT create commits; the orchestrator commits each stage for you.",
    "",
    "When the stage is fully complete, yield_to_parent with { done: true, notes }.",
  ].join("\n");
}

export function formatFindings(
  results: { instruction: string; findings: Finding[] }[],
): string {
  const lines: string[] = [];
  for (const { instruction, findings } of results) {
    if (findings.length === 0) continue;
    lines.push(`### ${instruction}`);
    for (const f of findings) {
      const loc = f.line !== undefined ? `${f.file}:${f.line}` : f.file;
      const sev = f.severity ? `[${f.severity}] ` : "";
      lines.push(`- ${sev}${loc} — ${f.comment}`);
    }
    lines.push("");
  }
  return lines.join("\n").trim();
}

export function buildAddressReviewPrompt(
  results: { instruction: string; findings: Finding[] }[],
  stage: Stage,
  index: number,
  total: number,
  planPath: string,
): string {
  return [
    `Code review of your changes for stage ${index}/${total} ("${stage.title}")`,
    "produced the following findings. Address each actionable item.",
    "",
    formatFindings(results),
    "",
    "Instructions:",
    "- Make the code changes needed to resolve these findings.",
    `- Document any resulting changes in the plan file (${planPath}).`,
    "- Do NOT create commits; the orchestrator commits for you.",
    "",
    "When done, yield_to_parent with { done: true, notes }.",
  ].join("\n");
}

function currentHead(repo: string): string {
  return git(repo, "rev-parse", "HEAD").trim();
}

/**
 * Drive a gated, stage-by-stage implementation of a plan:
 *   1. create a branch for the work,
 *   2. extract the plan's stages,
 *   3. for each stage: implement it, run code review over just that stage's
 *      changes, address any findings (looping up to MAX_REVIEW_ROUNDS), then
 *      commit the stage to the branch.
 */
export async function runImplementPlan({
  params,
  thread,
  log,
}: {
  params: ImplementPlanParams;
  thread: ThreadFn;
  log: LogFn;
}): Promise<{ branch: string; stages: Stage[] }> {
  const repo = params.repo ?? process.cwd();
  const planAbs = path.isAbsolute(params.plan)
    ? params.plan
    : path.join(repo, params.plan);
  if (!existsSync(planAbs)) {
    throw new Error(`Plan file not found: ${planAbs}`);
  }
  const planBody = readFileSync(planAbs, "utf8");

  const branch = params.branch ?? defaultBranchName(params.plan);
  git(repo, "checkout", "-b", branch);
  log(`Created branch ${branch}`);

  const { stages } = await thread<{ stages: Stage[] }>(
    buildExtractStagesPrompt(params.plan, planBody),
    STAGES_YIELD_SCHEMA,
  );
  if (stages.length === 0) {
    log("No stages found in the plan.");
    return { branch, stages };
  }
  log(`Plan has ${stages.length} stage(s).`);

  for (let i = 0; i < stages.length; i++) {
    const stage = stages[i];
    const n = i + 1;
    const baseRef = currentHead(repo);
    log(`Stage ${n}/${stages.length}: ${stage.title}`);

    await thread<{ done: boolean; notes?: string }>(
      buildImplementStagePrompt(stage, n, stages.length, params.plan),
      STAGE_DONE_YIELD_SCHEMA,
      { contextFiles: [planAbs], systemReminder: PLAN_MAINTENANCE_REMINDER },
    );

    for (let round = 1; round <= MAX_REVIEW_ROUNDS; round++) {
      const changed = getChangedPaths(repo, baseRef);
      if (changed.length === 0) {
        log(`Stage ${n}: no changes detected; skipping review.`);
        break;
      }
      const results = await runReview({
        params: { start: baseRef, repo },
        thread,
        log,
      });
      const findingCount = results.reduce((c, r) => c + r.findings.length, 0);
      if (findingCount === 0) {
        log(`Stage ${n}: review round ${round} clean.`);
        break;
      }
      if (round === MAX_REVIEW_ROUNDS) {
        log(
          `Stage ${n}: ${findingCount} finding(s) remain after ${MAX_REVIEW_ROUNDS} round(s); committing anyway.`,
        );
        break;
      }
      log(
        `Stage ${n}: review round ${round} found ${findingCount} finding(s); addressing.`,
      );
      await thread<{ done: boolean; notes?: string }>(
        buildAddressReviewPrompt(results, stage, n, stages.length, params.plan),
        STAGE_DONE_YIELD_SCHEMA,
        { contextFiles: [planAbs], systemReminder: PLAN_MAINTENANCE_REMINDER },
      );
    }

    git(repo, "add", "-A");
    git(repo, "commit", "-m", `Stage ${n}: ${stage.title}`);
    log(`Stage ${n}: committed.`);
  }

  log(`All ${stages.length} stage(s) complete on ${branch}.`);
  return { branch, stages };
}
