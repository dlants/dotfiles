---
name: search
description: Search the web.
---

```bash
cd ~/.claude/skills/search && pkgx uv run scripts/search.py "query"
```

### Options

- `--count <n>` — number of results (default 10, max 20)
- `--offset <n>` — pagination offset (default 0)
- `--country <code>` — country code, e.g. `US`, `GB` (default `US`)
- `--freshness <value>` — `pd` (past day), `pw` (past week), `pm` (past month), `py` (past year), or a date range `YYYY-MM-DDtoYYYY-MM-DD`
- `--raw` — print the full raw JSON response instead of the condensed result list
