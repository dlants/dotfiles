import { $ } from "zx";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  buildAddressReviewPrompt,
  buildImplementStagePrompt,
  defaultBranchName,
  detectWorktreeRoot,
  formatFindings,
  prepareImplementation,
  runImplementPlan,
  type Stage,
} from "./implement-plan-lib.ts";

function setupWorktreeRoot(withScript: boolean): {
  root: string;
  main: string;
} {
  const root = realpathSync(mkdtempSync(path.join(tmpdir(), "wt-root-")));
  $.sync`git -C ${root} init --bare .bare`;
  writeFileSync(path.join(root, ".git"), "gitdir: ./.bare\n");
  // Seed the bare repo's default branch via a temporary clone.
  const main = path.join(root, "main");
  $.sync`git -C ${root} worktree add -b main ${main}`;
  $.sync`git -C ${main} config user.email test@test.com`;
  $.sync`git -C ${main} config user.name test`;
  writeFileSync(path.join(main, "README.md"), "# repo\n");
  $.sync`git -C ${main} add -A`;
  $.sync`git -C ${main} commit -m init`;
  if (withScript) {
    const script = path.join(root, "new-worktree.sh");
    writeFileSync(
      script,
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
        'git -C "$ROOT" worktree add -b "$1" "$ROOT/$1"',
        "",
      ].join("\n"),
    );
  }
  return { root, main };
}

describe("defaultBranchName", () => {
  it("slugifies the plan basename", () => {
    const name = defaultBranchName("docs/My Plan.md");
    expect(name).toMatch(/^implement-my-plan-\d{8,14}$/);
  });
});

describe("formatFindings", () => {
  it("groups findings by instruction with locations", () => {
    const out = formatFindings([
      {
        instruction: "ts.instructions.md",
        findings: [
          { file: "a.ts", line: 3, severity: "warning", comment: "fix" },
        ],
      },
      { instruction: "empty.md", findings: [] },
    ]);
    expect(out).toContain("### ts.instructions.md");
    expect(out).toContain("[warning] a.ts:3 — fix");
    expect(out).not.toContain("empty.md");
  });
});

describe("prompt builders", () => {
  const stage: Stage = { title: "Set up types", summary: "Add the types." };

  it("implement prompt references the plan path and stage", () => {
    const p = buildImplementStagePrompt(stage, 1, 3, "PLAN.md");
    expect(p).toContain("Stage 1/3: Set up types");
    expect(p).toContain("PLAN.md");
    expect(p).toContain("commit your changes");
  });

  it("address prompt embeds findings", () => {
    const p = buildAddressReviewPrompt(
      [{ instruction: "ts", findings: [{ file: "a.ts", comment: "nit" }] }],
      stage,
      2,
      3,
      "PLAN.md",
    );
    expect(p).toContain('stage 2/3 ("Set up types")');
    expect(p).toContain("a.ts — nit");
  });
});

describe("runImplementPlan (temp git repo)", () => {
  let repo: string;

  function git(...args: string[]): string {
    return $.sync`git -C ${repo} ${args}`.stdout;
  }

  beforeEach(() => {
    repo = mkdtempSync(path.join(tmpdir(), "implement-plan-"));
    git("init");
    git("config", "user.email", "test@test.com");
    git("config", "user.name", "test");
    // A path-scoped instruction so review threads are spawned for *.ts changes.
    writeFileSync(
      path.join(repo, "PLAN.md"),
      "# Plan\n\nStage 1: foo\nStage 2: bar\n",
    );
    $.sync`git -C ${repo} add -A`;
    git("commit", "-m", "init");
  });

  afterEach(() => {
    $.sync`rm -rf ${repo}`;
  });

  it("creates a branch, runs a stage per stage, and commits each", async () => {
    const stages: Stage[] = [
      { title: "stage one", summary: "first" },
      { title: "stage two", summary: "second" },
    ];

    const prompts: string[] = [];
    let implementCount = 0;
    const thread = async (prompt: string) => {
      prompts.push(prompt);
      if (prompt.includes("Break the following implementation plan")) {
        return { stages };
      }
      if (prompt.includes("You are implementing ONE stage")) {
        // Simulate the implementing agent writing a file and committing it.
        implementCount++;
        const title = stages[implementCount - 1].title;
        writeFileSync(
          path.join(repo, `stage-${implementCount}.ts`),
          "export const x = 1;\n",
        );
        git("add", "-A");
        git("commit", "-m", `Stage ${implementCount}: ${title}`);
        return { done: true };
      }
      // Review threads: no instruction files exist, so runReview returns []
      // before ever calling thread; this branch should not be hit.
      return { findings: [] };
    };

    const logs: string[] = [];
    const result = await runImplementPlan({
      params: { plan: "PLAN.md", repo, branch: "feat/test" },
      thread: thread as never,
      log: (m) => logs.push(m),
    });

    expect(result.branch).toBe("feat/test");
    expect(result.stages).toHaveLength(2);
    expect(git("rev-parse", "--abbrev-ref", "HEAD").trim()).toBe("feat/test");

    const log = git("log", "--pretty=%s").trim().split("\n");
    expect(log).toContain("Stage 1: stage one");
    expect(log).toContain("Stage 2: stage two");
  });
});

describe("prepareImplementation (worktrees)", () => {
  const roots: string[] = [];

  afterEach(() => {
    for (const r of roots) $.sync`rm -rf ${r}`;
    roots.length = 0;
  });

  it("returns undefined worktree root for an ordinary repo", async () => {
    const repo = mkdtempSync(path.join(tmpdir(), "plain-"));
    roots.push(repo);
    $.sync`git -C ${repo} init`;
    expect(await detectWorktreeRoot(repo)).toBeUndefined();
  });

  it("detects the worktree root for a linked worktree", async () => {
    const { root, main } = setupWorktreeRoot(false);
    roots.push(root);
    const detected = await detectWorktreeRoot(main);
    expect(detected && path.resolve(detected)).toBe(path.resolve(root));
  });

  it("runs new-worktree.sh and copies the plan across", async () => {
    const { root, main } = setupWorktreeRoot(true);
    roots.push(root);
    const planAbs = path.join(main, "plans", "feature.md");
    mkdirSync(path.dirname(planAbs), { recursive: true });
    writeFileSync(planAbs, "# plan body\n");

    const logs: string[] = [];
    const result = await prepareImplementation({
      repo: main,
      planAbs,
      branch: "feat/x",
      log: (m) => logs.push(m),
    });

    const target = path.join(root, "feat/x");
    expect(path.resolve(result.repo)).toBe(path.resolve(target));
    expect(existsSync(target)).toBe(true);
    expect(
      $.sync`git -C ${target} rev-parse --abbrev-ref HEAD`.stdout.trim(),
    ).toBe("feat/x");
    expect(existsSync(result.planAbs)).toBe(true);
    expect(readFileSync(result.planAbs, "utf8")).toBe("# plan body\n");
  });

  it("creates a worktree itself when no script exists", async () => {
    const { root, main } = setupWorktreeRoot(false);
    roots.push(root);
    const planAbs = path.join(main, "feature.md");
    writeFileSync(planAbs, "# plan\n");

    const result = await prepareImplementation({
      repo: main,
      planAbs,
      branch: "feat/y",
      log: () => {},
    });

    const target = path.join(root, "feat/y");
    expect(existsSync(target)).toBe(true);
    expect(path.resolve(result.repo)).toBe(path.resolve(target));
    expect(existsSync(result.planAbs)).toBe(true);
  });
});
