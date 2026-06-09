---
name: fetch
description: Fetch a URL and extract its main text content as markdown.
---

```bash
curl "https://r.jina.ai/https://www.example.com"
```

Uses [Jina AI's Reader](https://jina.ai/reader/) to fetch a URL and return its
main content as clean markdown, stripping nav/ads/boilerplate. Just prefix the
target URL with `https://r.jina.ai/`. Handles JS-rendered pages server-side.
