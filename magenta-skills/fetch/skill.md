---
name: fetch
description: Fetch a URL and extract its main text content as markdown.
---

```bash
cd ~/.claude/skills/fetch && pkgx uv run scripts/fetch.py "https://example.com"
```

### Options

- `--format <fmt>` — `markdown` (default), `txt`, `html`, or `json`
- `--include-links` — keep hyperlinks
- `--include-images` — keep image references
- `--with-metadata` — prepend title / author / date

Uses trafilatura to strip nav/ads/boilerplate and return just the article body. For JS-rendered pages, use the `browser` skill instead.
