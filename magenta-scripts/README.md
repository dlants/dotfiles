# magenta-scripts

TypeScript scripts discovered by magenta from `~/.magenta/scripts` (this
directory is symlinked there via nix; see `nix/magenta-scripts.nix`).

Each `*.ts` file (except `*.test.ts`) is forked by magenta at startup so its
`registerScript(...)` call populates the catalog. Scripts import the SDK through
the `./magenta-sdk` shim that magenta maintains in the scripts directory.

- `code-review.ts` — registers the `code-review` script.
- `code-review-lib.ts` — dependency-free discovery/orchestration logic.
- `*.test.ts` — unit tests (run with `pnpm test`); excluded from discovery.
