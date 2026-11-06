import os from "node:os";
import path from "node:path";
import { serveWatcher } from "./magenta-sdk/watchers/index.ts";
import {
  makeScan,
  poll,
  type RepoSnapshot,
  render,
  summarize,
} from "./git-repo.ts";

/** Scoping knob: only paths under these roots are tracked. */
const ROOTS = ["~/src", "~/worktrees", "/src", "/infra"];
/** Repo roots (keys) never tracked, even when under ROOTS. */
const EXCLUDED = [path.join(os.homedir(), "src/benchling")];
const scanRoots = makeScan(ROOTS);

serveWatcher<RepoSnapshot>({
  manifest: new URL("./manifest.json", import.meta.url).pathname,
  scan: async (texts) =>
    (await scanRoots(texts)).filter((key) => !EXCLUDED.includes(key)),
  intervalMs: 10_000,
  // Threads re-subscribe keys they already track, so reject in poll as well.
  poll: (key) =>
    EXCLUDED.includes(key)
      ? Promise.resolve({ kind: "unavailable", error: "excluded" })
      : poll(key),
  summarize,
  render,
});
