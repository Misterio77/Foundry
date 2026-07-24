# Observation tools

All observation tools return the shared `state` and `sample` envelope documented
for [`get_game_context`](game-context.md). They read one focused snapshot on
RuneLite's client thread; calling the context tool does not also scan items,
prayers, or every skill.

## Skills

`get_skills` accepts an optional case-insensitive `names` array. Omitting it
returns every RuneLite skill.

```json
{
  "name": "get_skills",
  "arguments": {"names": ["Herblore", "Prayer"]}
}
```

Each result contains:

```json
{
  "name": "Herblore",
  "baseLevel": 70,
  "currentLevel": 74,
  "experience": 750000
}
```

`currentLevel - baseLevel` is the current boost or drain. The provisional
`skills` name and its `realLevel`/`boostedLevel` fields are removed rather than
aliased.

## Status effects

`get_status_effects` takes no arguments. While active, its `effects` object has
`availability: "current"` and contains:

- `boosts`: only skills whose current level differs from their base level, with
  `skill`, `baseLevel`, `currentLevel`, and signed `delta`;
- `activePrayers`: lowercase RuneLite prayer identifiers;
- `poison`: `none`, `poisoned`, or `venomed`, plus the next damage amount;
- `timers`: supported own-character buffs with `name` and `remainingTicks`.

Supported timers are stamina, antifire, super antifire, and the divine attack,
strength, defence, ranged, magic, combat, bastion, and battlemage potions. The
list contains only active timers. It intentionally excludes inferred boss or PvP
mechanics.

When the client is not active, availability is `not_logged_in`, arrays are empty,
and poison is null. Status is current-only and is never cached across transitions.

## Carried items

`get_carried_items` returns both inventory and equipment by default. An optional
`containers` array can request one or both explicitly:

```json
{
  "name": "get_carried_items",
  "arguments": {"containers": ["inventory"]}
}
```

Each requested container reports:

- `availability`: `current`, `not_logged_in`, or `unavailable`;
- fixed `capacity`, source occupied-slot count, and source total quantity;
- whether valid items beyond the hard capacity bound were omitted from `items`;
- a slot-ordered `items` array.

Items contain `slot`, numeric `id`, semantic `name`, `quantity`, `noted`, and
`stackable`. Equipment also includes a lowercase `slotName`. Empty slots are
omitted. Inventory output is bounded to 28 slots and equipment to 14 before
serialization. If a malformed or future container exceeds that bound, counts
still describe the full source while `truncated` makes omitted item details
explicit.

Generic charges are not exposed: RuneLite has no reliable item-independent charge
API, and guessing from names or unrelated plugin state would violate the typed,
current-data contract. Bank and auxiliary containers remain private and out of
this tool.
