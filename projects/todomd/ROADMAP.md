# todomd roadmap

Planned work, most valuable first. [DESIGN.md](DESIGN.md) holds the design these
build on.

## Editable fields

Summaries, completion, and list membership are the only editable fields, so due
dates, priorities, and categories can only be changed in the `.ics` file.

Due and start dates are the extension the design already anticipates. Priorities
and categories are currently listed as non-goals; adding them is a deliberate
reversal of that boundary, not an oversight to fix quietly.

Constraints:

- absence from Markdown must never delete or alter an existing property;
- ambiguous syntax must be a parse error rather than a guess; and
- the dialect must stay diffable and easy to type.

Open question: how fields appear. Trailing markers such as `!!!` for priority
and `@tag` for categories read naturally and match existing habits, but they
collide with ordinary summary text and need an exact grammar. A separate
metadata suffix avoids the collision at the cost of terseness.

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
