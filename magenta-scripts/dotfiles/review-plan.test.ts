import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { expect, it } from "vitest";
import { runScript } from "./magenta-sdk/testing.ts";
import { buildReviewPrefix } from "./review-plan-lib.ts";
import "./review-plan.ts";

it("reviews with a shared prefix and addresses findings", async () => {
  const repo = mkdtempSync(path.join(tmpdir(), "review-plan-"));
  writeFileSync(path.join(repo, "plan.md"), "# Plan\nDo the thing.\n");
  mkdirSync(path.join(repo, "perspectives"));
  writeFileSync(path.join(repo, "perspectives", "a.md"), "Check A.");
  writeFileSync(path.join(repo, "perspectives", "b.md"), "Check B.");
  const prefix = buildReviewPrefix("plan.md", "# Plan\nDo the thing.\n", repo);

  const { handle, donePromise } = runScript("review-plan", {
    plan: "plan.md",
    repo,
    instructions: "perspectives",
  });
  const first = await handle.nextThread();
  const second = await handle.nextThread();
  for (const call of [first, second]) {
    expect(call.prompt.startsWith(prefix)).toBe(true);
  }
  expect(first.prompt).toContain("Check A.");
  first.yield({ findings: [{ comment: "missing tests" }] });
  second.yield({ findings: [] });
  const address = await handle.nextThread();
  expect(address.prompt).toContain("missing tests");
  address.yield({ summary: "added tests" });
  await donePromise;
  expect(handle.logs).toContain("added tests");
});
