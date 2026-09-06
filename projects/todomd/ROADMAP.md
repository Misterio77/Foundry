# todomd roadmap

Planned work, most valuable first. [DESIGN.md](DESIGN.md) holds the design these
build on.

## Editable fields

Priority is editable through `!`, `!!`, and `!!!` markers. Due and start dates
and categories still have to be changed in the `.ics` file.

Due and start dates are the extension the design already anticipates.
Categories are listed as a non-goal; adding them is a deliberate reversal of
that boundary, as priority already was.

Constraints, all of which priority markers now demonstrate:

- absence from Markdown must never delete or alter an existing property;
- a value is written only when the rendered form changes, so representations the
  dialect flattens are not rewritten;
- ambiguous syntax must be a parse error rather than a guess; and
- the dialect must stay diffable and easy to type.

Quoting already exists for summaries whose start would otherwise read as syntax,
so new leading markers can reuse it instead of inventing an escape. Categories
remain the harder case: `@tag` is natural but unbounded, and tags can appear
anywhere in a line rather than only at its start.

## Configurable sorting

Tasks render unfinished first, then by priority, then alphabetically, with the
task identity breaking ties. Ordering is presentational, so changing it is safe:
the planner ignores line order.

The fixed default does not suit everything:

- 323 tasks already carry `X-APPLE-SORT-ORDER` from other clients, so a manual
  order exists in the data and is currently discarded;
- due date is an obvious sort key once dates are editable; and
- grouping by priority rather than sorting by it suits some lists better.

Likely shape: a configured list of sort keys, overridable per list. Whatever the
keys, rendering the same state must stay deterministic, since the accepted-state
refresh and any future watch mode compare rendered documents.

## Shell completions

`todo <TAB>` completed while todoman was installed; the replacement dropped it.
Generate completions with `clap_complete` during the Nix build, fish at minimum.

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
