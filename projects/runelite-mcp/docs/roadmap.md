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

### M1a — state and availability

- Run an intuition probe before choosing the replacement for the provisional
  `client_state` interface.
- Define one shared envelope for game state, sampling tick, availability,
  truncation, and errors.
- Add session/player identity, location, movement, animation, interaction target,
  combat level, hitpoints, prayer points, run energy, and special attack.
- Keep logged-out and loading responses useful without retaining player-bound
  values.

M1a exits when the probe results and chosen schema are documented, provisional
interfaces are replaced rather than aliased, protocol fixtures cover every state,
Pi verifies login/logout/loading transitions, and both Gradle and Nix checks pass.

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
