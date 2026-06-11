import { $ } from "zx";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  buildReviewPrompt,
  discoverApplicableInstructions,
  getChangedPaths,
  globsMatch,
  globToRegExp,
  parseFrontmatter,
  runReview,
} from "./code-review-lib.ts";

describe("parseFrontmatter", () => {
  it("parses an applyTo string and strips the body", () => {
    const { meta, body } = parseFrontmatter(
      `---\napplyTo: "**/*.ts"\n---\n\nReview TypeScript.\n`,
    );
    expect(meta.applyTo).toBe("**/*.ts");
    expect(body.trim()).toBe("Review TypeScript.");
  });

  it("parses an inline list and excludeAgent", () => {
    const { meta } = parseFrontmatter(
      `---\napplyTo: ["**/*.ts", "**/*.tsx"]\nexcludeAgent: code-review\n---\nbody\n`,
    );
    expect(meta.applyTo).toEqual(["**/*.ts", "**/*.tsx"]);
    expect(meta.excludeAgent).toBe("code-review");
  });

  it("returns the whole text as body when there is no frontmatter", () => {
    const { meta, body } = parseFrontmatter("just prose");
    expect(meta).toEqual({});
    expect(body).toBe("just prose");
  });
});

describe("globToRegExp / globsMatch", () => {
  it("matches nested paths with **", () => {
    expect(globToRegExp("**/*.ts").test("src/a/b.ts")).toBe(true);
    expect(globToRegExp("**/*.ts").test("a.ts")).toBe(true);
    expect(globToRegExp("**/*.ts").test("src/a.py")).toBe(false);
  });

  it("does not let * cross path segments", () => {
    expect(globToRegExp("src/*.ts").test("src/a.ts")).toBe(true);
    expect(globToRegExp("src/*.ts").test("src/a/b.ts")).toBe(false);
  });

  it("expands brace alternation", () => {
    expect(globsMatch(["**/*.{ts,tsx}"], ["src/a.tsx"])).toBe(true);
    expect(globsMatch(["**/*.{ts,tsx}"], ["src/a.js"])).toBe(false);
  });
});

describe("buildReviewPrompt", () => {
  it("embeds the instruction body and the diff command", () => {
    const prompt = buildReviewPrompt(
      { name: ".github/instructions/ts.instructions.md", body: "Be careful." },
      { start: "main", stop: "feature" },
    );
    expect(prompt).toContain("git diff main..feature");
    expect(prompt).toContain("ts.instructions.md");
    expect(prompt).toContain("Be careful.");
  });
});

describe("discovery + runReview (temp git repo)", () => {
  let repo: string;

  function git(...args: string[]): void {
    $.sync`git -C ${repo} ${args}`;
  }

  function write(rel: string, content: string): void {
    const abs = path.join(repo, rel);
    mkdirSync(path.dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  }

  beforeEach(() => {
    repo = mkdtempSync(path.join(tmpdir(), "code-review-"));
    git("init");
    git("config", "user.email", "test@test.com");
    git("config", "user.name", "test");
    write(".github/copilot-instructions.md", "Repo-wide rules.\n");
    write(
      ".github/instructions/ts.instructions.md",
      `---\napplyTo: "**/*.ts"\n---\nTypeScript rules.\n`,
    );
    write(
      ".github/instructions/py.instructions.md",
      `---\napplyTo: "**/*.py"\n---\nPython rules.\n`,
    );
    write("README.md", "hello\n");
    git("add", "-A");
    git("commit", "-m", "init");
  });

  afterEach(() => {
    rmSync(repo, { recursive: true, force: true });
  });

  it("detects untracked changes and selects matching instructions", async () => {
    write("src/a.ts", "export const x = 1;\n");
    const changed = await getChangedPaths(repo, "HEAD");
    expect(changed).toContain("src/a.ts");

    const instructions = discoverApplicableInstructions(repo, changed);
    const names = instructions.map((i) => i.name);
    expect(names).toContain(".github/copilot-instructions.md");
    expect(names).toContain(".github/instructions/ts.instructions.md");
    expect(names).not.toContain(".github/instructions/py.instructions.md");
  });

  it("spawns one thread per applicable instruction and aggregates findings", async () => {
    write("src/a.ts", "export const x = 1;\n");

    const prompts: string[] = [];
    const logs: string[] = [];
    const thread = async (prompt: string) => {
      prompts.push(prompt);
      return { findings: [{ file: "src/a.ts", comment: "nit" }] };
    };

    const results = await runReview({
      params: { start: "HEAD", repo },
      thread: thread as never,
      log: (m: string) => logs.push(m),
    });

    expect(results).toHaveLength(2);
    expect(prompts).toHaveLength(2);
    // The TypeScript guideline body is reviewed; the Python one is not.
    expect(prompts.some((p) => p.includes("TypeScript rules."))).toBe(true);
    expect(prompts.some((p) => p.includes("Python rules."))).toBe(false);
    expect(logs.some((l) => l.includes("2 finding(s)"))).toBe(true);
  });

  it("returns early when nothing changed", async () => {
    const logs: string[] = [];
    const results = await runReview({
      params: { start: "HEAD", repo },
      thread: (async () => {
        throw new Error("should not spawn");
      }) as never,
      log: (m: string) => logs.push(m),
    });
    expect(results).toEqual([]);
    expect(logs.some((l) => l.includes("No changed files"))).toBe(true);
  });
});
