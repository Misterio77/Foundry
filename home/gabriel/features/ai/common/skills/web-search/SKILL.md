---
name: web-search
description: Search the web with the web-search CLI using Gabs's Kagi subscription. Use when you need current information, external documentation, sources, or URLs to investigate a question. Read full result pages with the web-fetch skill.
---

# Web search

Use `web-search` to find titles, URLs, and snippets:

```bash
web-search "query"
web-search --count 5 "query"
web-search --json "query"
```

`--count N` (or `-n N`) accepts 1–20 results; the default is 8.
`--json` prints an array of `{title, url, snippet}` objects.
Use `--help` for CLI usage.

Authentication is handled by the CLI. `KAGI_SESSION_TOKEN_FILE` overrides
`/run/secrets/kagi_session_token`. Do not read the token into context.

Search snippets are previews, not full sources. Use the web-fetch skill to read
relevant result pages before relying on their details.
