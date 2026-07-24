# Roadmap

## M0 — foundation (current)

- Plugin Hub-compatible Java scaffold with no new runtime dependencies.
- Loopback Streamable HTTP transport and MCP protocol skeleton.
- Live client snapshot boundary, basic tools/resource/prompt, and unit tests.
- Requirements, architecture, test strategy, and explicit policy boundary.

## M1 — observational core

- Session/player state, skills, boosts, location, movement, interaction, inventory,
  equipment, prayers, effects, and bounded nearby-entity queries.
- Availability/freshness model shared by every capability.
- Bounded game-event ring buffer and `events` query tool.
- MCP Inspector and Pi compatibility suite.

## M2 — progression and private state

- Quests, diaries, combat achievements, Slayer, collection log, Grand Exchange,
  bank and auxiliary containers.
- Explicit per-category privacy controls, disabled by default for sensitive data.
- Search/pagination APIs rather than context-sized dumps.

## M3 — knowledge services

- OSRS Wiki search/page resources and item prices.
- Visible configuration warnings for any third-party requests and their payloads.
- Cache, timeout, rate-limit, and upstream attribution behavior.
- Retire equivalent tools from the detached MCP once parity is demonstrated.

## M4 — release hardening

- Full state-transition, performance, privacy, and malformed-input matrix.
- Plugin Hub submission metadata, icon, screenshots, and user documentation.
- External review of game-rule compliance and local transport security.
- Migration/removal plan for `home/gabriel/features/ai/mcp/osrs`.

Milestones are capability gates, not promises to expose everything RuneLite can
observe. Anything that makes prohibited gameplay easier in a RuneLite-disallowed
way remains out of scope even if technically read-only.
