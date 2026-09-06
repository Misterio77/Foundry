# todomd roadmap

Planned work, most valuable first. [DESIGN.md](DESIGN.md) holds the design these
build on.

## Categories

Categories still have to be changed in the `.ics` file. Adding them is a
deliberate reversal of the original scope boundary, as priority and dates
already were.

`@tag` is natural but unbounded, and tags can appear anywhere in a line rather
than only at its start. The syntax must remain unambiguous and preserve source
representations unless the rendered category set changes.

## Configurable sorting

Tasks render unfinished first, then by priority, then alphabetically, with the
task identity breaking ties. Ordering is presentational, so changing it is safe:
the planner ignores line order.

The fixed default does not suit everything:

- 323 tasks already carry `X-APPLE-SORT-ORDER` from other clients, so a manual
  order exists in the data and is currently discarded;
- due date is now available as a sort key; and
- grouping by priority rather than sorting by it suits some lists better.

Likely shape: a configured list of sort keys, overridable per list. Whatever the
keys, rendering the same state must stay deterministic, since the accepted-state
refresh and any future watch mode compare rendered documents.

## Watch mode

`edit --watch` applies valid Markdown saves automatically and rerenders when the
selected vdirs change. The design is settled and the architecture already
satisfies its requirements.

Remaining decisions: the event-watching abstraction, debounce and self-write
suppression, conflict and recovery commands, and a durable crash-recovery
protocol.

## List inventory

`show` reports tasks, so a list with nothing in scope does not appear and the
set of list names is not discoverable from the command surface.

A `todomd lists` command printing display names, and probably their directories
and task counts, closes that.
