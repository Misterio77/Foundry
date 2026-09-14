# todomd roadmap

Planned work, most valuable first. [DESIGN.md](DESIGN.md) holds the design these
build on.

## Richer LSP editing

Live editing already covers diagnostics, save-triggered transactions,
source-directory watching, canonical buffer refreshes, and conflict reporting.
Completion, hover, document symbols, repair code actions, and richer conflict
recovery can build on that protocol.

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
keys, rendering the same state must stay deterministic, since accepted-state
refreshes and live synchronization compare rendered documents.

## List inventory

`show` reports tasks, so a list with nothing in scope does not appear and the
set of list names is not discoverable from the command surface.

A `todomd lists` command printing display names, and probably their directories
and task counts, closes that.
