# Game context interface

## Decision

A cold intuition probe asked three isolated `gpt-5.6-luna` samples for the
read-only MCP interface they expected from an embedded MMORPG client. All three
expected an argument-free tool with explicit active/loading/logged-out behavior
and MCP structured content; two preferred one combined session/player snapshot.
The resulting interface conforms to that familiar shape while retaining raw
RuneLite state for diagnostic precision.

The provisional `client_state` tool and `runelite://client/state` resource are
removed rather than aliased. Before 1.0, clients should discover capabilities
instead of assuming compatibility.

## Tool

Call `get_game_context` without selectors:

```json
{
  "name": "get_game_context",
  "arguments": {}
}
```

An active response has this structured content:

```json
{
  "state": "active",
  "sample": {
    "gameState": "LOGGED_IN",
    "tick": 123
  },
  "session": {
    "world": 301,
    "accountType": "NORMAL"
  },
  "player": {
    "name": "Gabs",
    "combatLevel": 126,
    "location": {
      "x": 3200,
      "y": 3200,
      "plane": 0,
      "regionId": 12850
    },
    "movement": {
      "moving": false,
      "animationId": -1,
      "poseAnimationId": 808
    },
    "interaction": null,
    "vitals": {
      "hitpoints": {"current": 99, "max": 99},
      "prayer": {"current": 77, "max": 77},
      "runEnergyPercent": 100.0,
      "specialAttackPercent": 100.0
    }
  }
}
```

Loading and logged-out states are successful results, not tool errors:

```json
{
  "state": "loading",
  "sample": {"gameState": "HOPPING", "tick": 124},
  "session": {"world": null, "accountType": null},
  "player": null
}
```

```json
{
  "state": "logged_out",
  "sample": {"gameState": "LOGIN_SCREEN", "tick": 0},
  "session": {"world": null, "accountType": null},
  "player": null
}
```

The same payload is available as the `runelite://game/context` resource. The
`skills` tool remains separate and returns `state`, `sample`, and its filtered
skill list.

## Field semantics

- `state` is the stable MCP-facing state: `active`, `loading`, or `logged_out`.
- `sample.gameState` is RuneLite's exact `GameState`; `sample.tick` is the server
  tick at which the client-thread snapshot was taken.
- Session and player values are current only when `state` is `active`. They are
  explicitly null during transitions and after logout; no previous snapshot is
  cached.
- `movement.moving` means RuneLite currently has a local movement destination.
  Animation IDs are raw RuneLite IDs, with `-1` meaning no primary animation.
- NPC interactions include type, ID, name, and combat level. Player interactions
  omit identity by design and include only type and combat level.
- Hitpoints and prayer report boosted/current and real/max levels. Run energy and
  special attack are percentages and may contain fractional values.
- Tool results include identical JSON in `structuredContent` and the text fallback.

The probe's unanimous request for subscriptions is deferred. The transport stays
stateless for M1a; callers use `sample.tick` to detect freshness and poll only when
needed.
