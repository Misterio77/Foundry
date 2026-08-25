---
name: runelite-query
description: Read live RuneLite and OSRS account state through Gabs's local RuneLite Query HTTP API. Use for questions involving the current RuneLite session, skills, inventory, equipment, effects, progression, Slayer, Grand Exchange, observed bank items, wealth, collection log, POH, prices, or recent game events.
---

# RuneLite Query

Use the read-only API at `http://127.0.0.1:18471`. It observes gameplay but cannot perform actions.

Before an unfamiliar request, confirm RuneLite and the plugin are running and inspect the on-demand API description:

```bash
curl -fsS http://127.0.0.1:18471/v1/health | jq
curl -fsS http://127.0.0.1:18471/v1/openapi.json | jq '.paths'
```

Query endpoints directly with `curl`; compose results with `jq`. Repeated query parameters select multiple values:

```bash
curl -fsS http://127.0.0.1:18471/v1/context | jq
curl -fsS 'http://127.0.0.1:18471/v1/skills?name=Herblore&name=Prayer' | jq
curl -fsS 'http://127.0.0.1:18471/v1/stored-items?container=bank&query=rune&limit=20' | jq
```

Treat `loading`, `logged_out`, `unavailable`, `observed`, `stale`, `partial`, and truncation metadata literally. Never present unavailable or cached data as current. Event cursors are generation-bound; follow the cursor fields returned by `/v1/events` rather than inventing sequence numbers.
