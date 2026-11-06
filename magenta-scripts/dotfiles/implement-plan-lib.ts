import { $ } from "zx";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
} from "node:fs";
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
  /**
   * Absolute path to the git repository to implement the plan in. Required:
   * the forked script process's cwd is magenta's own install directory, not
   * the project you have open, so it cannot be inferred reliably.
   */
  repo: string;
  /** Branch to create for the implementation (defaults to a generated name). */
  branch?: string;
  /**
   * Create a new branch/worktree for the implementation. By default the script
   * develops in-place against the current branch in `repo`.
   */
  newBranch?: boolean;
};

export type Stage = {
  title: string;
  summary: string;
};


/** Recurring reminder injected into implement/address threads. */
export const PLAN_MAINTENANCE_REMINDER =
  "You are implementing a plan stage by stage. The plan file is the only channel " +
  "for reporting status: your yield carries no free text. Keep the plan updated as " +
  "you work: mark the stage's status (Done / In progress / Blocked), check off " +
  "completed items, record decisions and deviations, and for unfinished work write " +
  "concrete next steps or the blocker so the next agent (or the user) can pick up " +
  "from the plan alone. Restructure later stages if the work shows the plan should change.";

export const IMPLEMENT_PLAN_PARAM_SCHEMA = {
  type: "object",
  properties: {
    plan: {
      type: "string",
      description: "Path to the plan file (absolute or relative to the repo).",
    },
    repo: {
      type: "string",
      description:
        "Absolute path to the git repository to implement the plan in.",
    },
    branch: {
      type: "string",
      description:
        "Branch to create for the implementation. Defaults to a generated name.",
    },
    newBranch: {
      type: "boolean",
      description:
        "Create a new branch/worktree for the implementation. Defaults to developing in-place against the current branch.",
    },
  },
  required: ["plan", "repo"],
} as const;

export type NavigatorResult =
  | { action: "implement"; title: string; summary: string }
  | { action: "done" };

// Anthropic rejects oneOf/anyOf/allOf at the top level of a tool input schema,
// so the variants are flattened into one object with conditionally-used fields.
export const NAVIGATOR_YIELD_SCHEMA = {
  type: "object",
  properties: {
    action: { enum: ["implement", "done"] },
    title: {
      type: "string",
      description: 'Required when action is "implement": the stage title.',
    },
    summary: {
      type: "string",
      description:
        'Required when action is "implement": one or two sentences describing the stage scope.',
    },
  },
  required: ["action"],
  additionalProperties: false,
} as const;

export type StageResult = {
  status: "complete" | "incomplete-proceed" | "incomplete-blocked";
};

export const STAGE_DONE_YIELD_SCHEMA = {
  type: "object",
  properties: {
    status: {
      enum: ["complete", "incomplete-proceed", "incomplete-blocked"],
    },
  },
  required: ["status"],
  additionalProperties: false,
} as const;

const STAGE_YIELD_INSTRUCTIONS = [
  "Before yielding, record the stage's status, progress, decisions, and any next steps or blockers in the plan file. The yield carries only a status; anything you want the next agent or the user to know must be in the plan.",
  'When complete and committed, yield_to_parent with { status: "complete" }.',
  'If unfinished but another implementation thread can continue from the plan notes, yield with { status: "incomplete-proceed" }.',
  'If blocked and unable to proceed, yield with { status: "incomplete-blocked" }.',
].join("\n");

async function git(repo: string, ...args: string[]): Promise<string> {
  const result = await $`git -C ${repo} ${args}`;
  return result.stdout;
}

/**
 * If `repo` is a linked git worktree (its git-dir differs from the shared
 * git-common-dir), return the directory that contains the worktrees — the
 * parent of the common dir. For the bare-repo + worktrees layout this is the
 * project root that holds `main/`, the sibling worktrees, and `new-worktree.sh`.
 * Returns undefined for an ordinary, non-worktree checkout.
 */
export async function detectWorktreeRoot(
  repo: string,
): Promise<string | undefined> {
  const common = (
    await $`git -C ${repo} rev-parse --path-format=absolute --git-common-dir`.nothrow()
  ).stdout.trim();
  const gitDir = (
    await $`git -C ${repo} rev-parse --path-format=absolute --git-dir`.nothrow()
  ).stdout.trim();
  if (!common || !gitDir) return undefined;
  if (path.resolve(common) === path.resolve(gitDir)) return undefined;
  return path.dirname(common);
}

/** Best-effort detection of the repo's default branch (for seeding worktrees). */
export async function detectDefaultBranch(repo: string): Promise<string> {
  const head = (
    await $`git -C ${repo} symbolic-ref --quiet refs/remotes/origin/HEAD`.nothrow()
  ).stdout.trim();
  if (head) return head.replace(/^refs\/remotes\/origin\//, "");
  for (const candidate of ["main", "master"]) {
    const r =
      await $`git -C ${repo} show-ref --verify --quiet refs/heads/${candidate}`.nothrow();
    if (r.exitCode === 0) return candidate;
  }
  return "main";
}

/**
 * Prepare the working directory for the implementation and ensure `branch`
 * exists, returning the repo dir and plan path to actually operate on.
 *
 * - Not a worktree: create `branch` in-place (the original behavior).
 * - A worktree with `new-worktree.sh`: run that script to spin up a fresh
 *   sibling worktree for `branch` (seeded from `main/`).
 * - A worktree without the script: create the worktree ourselves from the
 *   default branch.
 *
 * In the worktree cases the plan file is copied into the new worktree if it
 * didn't come across (it is usually untracked, so it won't).
 */
export async function prepareImplementation({
  repo,
  planAbs,
  branch,
  newBranch,
  log,
}: {
  repo: string;
  planAbs: string;
  branch: string;
  newBranch?: boolean;
  log: LogFn;
}): Promise<{ repo: string; planAbs: string }> {
  if (!newBranch) {
    log(`Developing in-place against the current branch in ${repo}`);
    return { repo, planAbs };
  }

  const worktreeRoot = await detectWorktreeRoot(repo);
  if (!worktreeRoot) {
    await git(repo, "checkout", "-b", branch);
    log(`Created branch ${branch}`);
    return { repo, planAbs };
  }

  const target = path.join(worktreeRoot, branch);
  if (existsSync(target)) {
    throw new Error(`Worktree target already exists: ${target}`);
  }

  const script = path.join(worktreeRoot, "new-worktree.sh");
  if (existsSync(script)) {
    log(`Running new-worktree.sh for ${branch}`);
    await $`bash ${script} ${branch}`;
  } else {
    const base = await detectDefaultBranch(repo);
    log(`No new-worktree.sh found; creating worktree ${branch} from ${base}`);
    await git(repo, "worktree", "add", "-b", branch, target, base);
  }

  if (!existsSync(target)) {
    throw new Error(`Worktree was not created at ${target}`);
  }

  const planRel = path.relative(repo, planAbs);
  const newPlanAbs =
    planRel.startsWith("..") || path.isAbsolute(planRel)
      ? path.join(target, path.basename(planAbs))
      : path.join(target, planRel);
  if (!existsSync(newPlanAbs)) {
    mkdirSync(path.dirname(newPlanAbs), { recursive: true });
    copyFileSync(planAbs, newPlanAbs);
    log(`Copied plan into worktree: ${newPlanAbs}`);
  }

  log(`Implementing in worktree ${target}`);
  return { repo: target, planAbs: newPlanAbs };
}

export function defaultBranchName(planPath: string): string {
  const base = path
    .basename(planPath)
    .replace(/\.[^.]+$/, "")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  const stamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14);
  return `implement-${base || "plan"}-${stamp}`;
}

export function buildNavigatorPrompt(
  planPath: string,
  planBody: string,
  completed: Stage[],
): string {
  const done = completed.length
    ? completed.map((s, i) => `${i + 1}. ${s.title}`).join("\n")
    : "(none yet)";
  return [
    "You are navigating the implementation of a plan. Decide what single stage",
    "should be implemented NEXT, or whether the plan is fully implemented.",
    "The plan may have been revised by previous implementation agents; trust its",
    "current recorded status and structure. Inspect the repo (e.g. git log) if",
    "needed to verify progress.",
    "",
    `Plan file: ${planPath}`,
    "",
    "Stages completed so far in this run:",
    done,
    "",
    "--- BEGIN PLAN ---",
    planBody.trim(),
    "--- END PLAN ---",
    "",
    "Do not implement anything or edit files. When done, yield_to_parent with",
    '{ action: "implement", title, summary } for the next independently committable',
    'stage, or { action: "done" } if nothing remains.',
  ].join("\n");
}

export function buildImplementStagePrompt(
  stage: Stage,
  index: number,
  planPath: string,
): string {
  return [
    "You are implementing ONE stage of an implementation plan.",
    "",
    `Plan file: ${planPath}`,
    "Read the full plan before starting so you understand the surrounding context.",
    "",
    `## Stage ${index}: ${stage.title}`,
    stage.summary,
    "",
    "Instructions:",
    "- Work autonomously and unsupervised: do not ask for confirmation; make",
    "  reasonable decisions and proceed.",
    "- Implement ONLY this stage. Do not begin work that belongs to later stages.",
    "- Work until this stage is fully complete, including tests where appropriate.",
    "- Before you are done, make sure the ENTIRE project is green: ALL tests,",
    "  typechecks, and lints must pass (not just the ones for files you touched).",
    "  Run the project's full test, typecheck, and lint commands and fix any",
    "  failures you introduced.",
    `- Record status, progress, and decisions directly in the plan file`,
    `  (${planPath}): mark this stage's status, check off completed items, and`,
    "  record decisions/deviations so the plan stays an accurate reflection of the work.",
    "- Only once all tests, typechecks, and lints pass, commit your changes with",
    `  a descriptive message (e.g. \"Stage ${index}: ${stage.title}\").`,
    "",
    STAGE_YIELD_INSTRUCTIONS,
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
  planPath: string,
): string {
  return [
    `Code review of your changes for stage ${index} ("${stage.title}")`,
    "produced the following findings. Address each actionable item.",
    "",
    formatFindings(results),
    "",
    "Instructions:",
    "- Work autonomously and unsupervised: do not ask for confirmation.",
    "- Make the code changes needed to resolve these findings.",
    `- Document any resulting changes or decisions in the plan file (${planPath}).`,
    "- Before you are done, make sure the ENTIRE project is green: ALL tests,",
    "  typechecks, and lints must pass. Run the project's full test, typecheck,",
    "  and lint commands and fix any failures.",
    "- Only once all tests, typechecks, and lints pass, commit your changes with",
    "  a descriptive message.",
    "",
    STAGE_YIELD_INSTRUCTIONS,
  ].join("\n");
}

async function currentHead(repo: string): Promise<string> {
  return (await git(repo, "rev-parse", "HEAD")).trim();
}

/**
 * Drive a gated, stage-by-stage implementation of a plan:
 *   1. create a branch for the work,
 *   2. extract the plan's stages,
 *   3. for each stage: an agent implements it and commits, then code review
 *      runs over just that stage's changes and (if there are findings) an agent
 *      addresses them and commits. The agents own their commits.
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
  const planCandidates = path.isAbsolute(params.plan)
    ? [params.plan, path.join(params.repo, params.plan.replace(/^\/+/, ""))]
    : [path.join(params.repo, params.plan), params.plan];
  const planParamAbs = planCandidates.find((p) => existsSync(p));
  if (!planParamAbs) {
    throw new Error(
      `Plan file not found. Tried: ${planCandidates.join(", ")}`,
    );
  }
  const branch = params.branch ?? defaultBranchName(params.plan);
  const { repo, planAbs } = await prepareImplementation({
    repo: params.repo,
    planAbs: planParamAbs,
    branch,
    newBranch: params.newBranch,
    log,
  });
  const planLabel = path.relative(repo, planAbs);
  const completed: Stage[] = [];

  async function implementUntilComplete(
    prompt: string,
    stageNumber: number,
  ): Promise<boolean> {
    let continuation = "";
    while (true) {
      const result = await thread<StageResult>(
        prompt + continuation,
        STAGE_DONE_YIELD_SCHEMA,
        {
          cwd: repo,
          contextFiles: [planAbs],
          systemReminder: PLAN_MAINTENANCE_REMINDER,
        },
      );
      switch (result.status) {
        case "complete":
          log(`Stage ${stageNumber}: complete.`);
          return true;
        case "incomplete-proceed":
          log(`Stage ${stageNumber}: incomplete; continuing.`);
          continuation = `\n\nA previous implementation thread left this stage incomplete. Continue from the existing work; its progress and next steps are recorded in the plan file (${planLabel}).`;
          break;
        case "incomplete-blocked":
          log(`Stage ${stageNumber}: blocked. See ${planLabel} for details.`);
          return false;
        default:
          throw new Error("Invalid stage implementation result");
      }
    }
  }

  for (let n = 1; ; n++) {
    const next = await thread<NavigatorResult>(
      buildNavigatorPrompt(planLabel, readFileSync(planAbs, "utf8"), completed),
      NAVIGATOR_YIELD_SCHEMA,
      { cwd: repo },
    );
    if (next.action === "done") break;
    if (next.action !== "implement" || !next.title) {
      throw new Error("Invalid navigator result");
    }
    const stage: Stage = { title: next.title, summary: next.summary ?? "" };
    const baseRef = await currentHead(repo);
    log(`Stage ${n}: ${stage.title}`);

    if (
      !(await implementUntilComplete(
        buildImplementStagePrompt(stage, n, planLabel),
        n,
      ))
    ) return { branch, stages: completed };

    const changed = await getChangedPaths(repo, baseRef);
    if (changed.length === 0) {
      log(`Stage ${n}: no changes detected; skipping review.`);
      completed.push(stage);
      continue;
    }

    const results = await runReview({
      params: { start: baseRef, repo },
      thread,
      log,
    });
    const findingCount = results.reduce((c, r) => c + r.findings.length, 0);
    if (findingCount === 0) {
      log(`Stage ${n}: review clean.`);
      completed.push(stage);
      continue;
    }

    log(`Stage ${n}: review found ${findingCount} finding(s); addressing.`);
    if (
      !(await implementUntilComplete(
        buildAddressReviewPrompt(results, stage, n, planLabel),
        n,
      ))
    ) return { branch, stages: completed };
    log(`Stage ${n}: review addressed.`);
    completed.push(stage);
  }

  log(`All ${completed.length} stage(s) complete on ${branch}.`);
  return { branch, stages: completed };
}
