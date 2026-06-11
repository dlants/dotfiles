import { $ } from "zx";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  buildAddressReviewPrompt,
  buildImplementStagePrompt,
  defaultBranchName,
  formatFindings,
  runImplementPlan,
  type Stage,
} from "./implement-plan-lib.ts";

describe("defaultBranchName", () => {
  it("slugifies the plan basename", () => {
    const name = defaultBranchName("docs/My Plan.md");
    expect(name).toMatch(/^implement\/my-plan-\d{8,14}$/);
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
