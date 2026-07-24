# Roadmap

## M0 — foundation (complete)

- Plugin Hub-shaped Java project with no additional runtime dependencies.
- Stateless loopback Streamable HTTP transport and MCP `2025-11-25` support.
- Client-thread snapshot boundary, basic tools/resource/prompt, and automated
  protocol/transport tests.
- Reproducible Nix package, Home Manager sideload installation, and patched
  developer-mode RuneLite launch.
- End-to-end Pi verification across logged-in, logged-out, disabled, and
  re-enabled states.
- Requirements, architecture, test strategy, and explicit policy boundary.

## M1 — observational core

### M1a — state and availability (complete)

- A three-sample cold intuition probe informed the documented
  [`get_game_context` interface](game-context.md).
- One shared envelope carries normalized state, exact RuneLite game state, and
  sampling tick.
- Session/player identity, location, movement, animation, interaction target,
  combat level, hitpoints, prayer points, run energy, and special attack are live.
- Provisional interfaces were replaced rather than aliased.
- Automated fixtures cover every RuneLite game state and stale-data transitions.
- Pi verified active play, movement, world-hop `HOPPING`/`LOADING`, transient
  logged-in-without-player, recovery, and logout against the packaged plugin.
- Gradle checks and the reproducible Nix package build pass.

### M1b — skills, effects, and carried items

- Refine skill filtering and represent temporary boosts consistently.
- Add active prayers, poison/venom, boosts, timers, and relevant status effects.
- Add inventory and equipment with semantic item names, quantities, charges where
  reliable, container availability, total counts, and hard output bounds.
- Verify inventory/widget open and closed transitions through Pi.

### M1c — event history

- Maintain a bounded in-memory ring of selected RuneLite events.
- Cover state transitions, XP gains, loot, inventory/equipment changes, movement,
  and interaction changes where RuneLite exposes reliable events.
- Add filtered, paginated event queries with sequence/tick metadata.
- Never persist history or include private chat/social events.

### M1d — bounded world context

- Add narrowly scoped NPC, object, ground-item, widget, and map queries only after
  a policy review of each shape.
- Bound distance, result count, fields, and computation before serialization.
- Omit nearby player identities by default and prohibit PvP scouting, boss
  prediction, prayer recommendations, and automatic safe-tile derivation.

## M2 — progression and private state

- Quests, diaries, combat achievements, Slayer, collection log, Grand Exchange,
  bank, and auxiliary containers.
- Explicit per-category privacy controls, disabled by default for sensitive data.
- Search/pagination APIs rather than context-sized dumps.

## M3 — knowledge services

- OSRS Wiki search/page resources and item prices.
- Visible configuration warnings for any third-party requests and their payloads.
- Cache, timeout, rate-limit, and upstream attribution behavior.

## M4 — release hardening

- Full state-transition, performance, privacy, and malformed-input matrix.
- MCP Inspector plus a second independent MCP client compatibility suite.
- Plugin Hub submission metadata, icon, screenshots, and user documentation.
- External review of game-rule compliance and local transport security.

Milestones are capability gates, not promises to expose everything RuneLite can
observe. Anything that makes prohibited gameplay easier in a RuneLite-disallowed
way remains out of scope even if technically read-only.
