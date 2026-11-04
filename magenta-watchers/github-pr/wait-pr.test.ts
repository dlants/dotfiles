import assert from "node:assert/strict";
import { test } from "node:test";
import { render } from "./pull-request.ts";
import { makePredicate } from "./wait-pr.ts";

type Check = { name: string; status: string; url?: string };
type Comment = { id: string; url: string; updatedAt?: string };
function ctx(checks: Check[], comments: Comment[] = []): string {
  return render({
    pr: {
      ref: { url: "https://github.com/dlants/x/pull/1", owner: "dlants", repo: "x", number: 1 },
      title: "t",
      state: "open",
      draft: false,
      headSha: "abc",
      checks: checks as never,
      comments: comments.map((c) => ({
        kind: "issue_comment",
        author: "a",
        body: "hi",
        updatedAt: "2026-01-01",
        ...c,
      })) as never,
      truncated: false,
    },
  } as never);
}

test("green", () => {
  const pending = ctx([{ name: "ci", status: "pending", url: "https://x/1" }]);
  const green = ctx([{ name: "ci", status: "success" }, { name: "lint", status: "skipped" }]);
  const failing = ctx([{ name: "ci", status: "failure" }]);
  const p = makePredicate("green", pending);
  assert.equal(p(pending), false);
  assert.equal(p(failing), false);
  assert.equal(p(green), true);
  assert.equal(makePredicate("green", green)(green), true, "already green");
});

test("new-failure ignores pre-existing failures", () => {
  const start = ctx([{ name: "a", status: "failure" }, { name: "b", status: "pending" }]);
  const p = makePredicate("new-failure", start);
  assert.equal(p(start), false);
  assert.equal(p(ctx([{ name: "a", status: "failure" }, { name: "b", status: "success" }])), false);
  assert.equal(p(ctx([{ name: "a", status: "failure" }, { name: "b", status: "failure", url: "https://x/2" }])), true);
});

test("new-comment ignores existing comments", () => {
  const start = ctx([], [{ id: "1", url: "https://c/1" }]);
  const p = makePredicate("new-comment", start);
  assert.equal(p(start), false);
  assert.equal(p(ctx([], [{ id: "1", url: "https://c/1", updatedAt: "2026-02-02" }])), false);
  assert.equal(p(ctx([], [{ id: "1", url: "https://c/1" }, { id: "2", url: "https://c/2" }])), true);
});
