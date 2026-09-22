# todomd roadmap

Planned work, most valuable first. [DESIGN.md](DESIGN.md) holds the design these
build on.

## Session ergonomics

The explicit create/apply/close lifecycle can grow two convenience commands:

- `session refresh` to accept inbound ICS state without treating the current
  Markdown as an outgoing edit; and
- `session edit --lsp/--no-lsp` to open an existing session in either live or
  manual mode.

Top-level `edit` can then become an orchestrator over the same session
primitives. `show` should continue sharing repository loading and projection
without creating runtime state.

## Richer LSP editing

Live editing already covers diagnostics, save-triggered transactions,
source-directory watching, canonical buffer refreshes, and conflict reporting.
Completion, hover, document symbols, repair code actions, and richer conflict
recovery can build on that protocol.

## Persistent manual ordering

Views configure grouping and sorting, and the `manual` key reads
`X-APPLE-SORT-ORDER` values written by Apple Reminders, Nextcloud Tasks, and
Tasks.org. Markdown line order remains presentational, however, so rearranging
siblings does not write those values yet.

Persistent ordering should use sparse integer ranks so ordinary moves touch one
task rather than incrementing `SEQUENCE` across a whole list. Rebalancing must
account for completed roots and descendants hidden from the active scope; it
cannot safely renumber only the visible document.

## List inventory

`show` reports tasks, so a list with nothing in scope does not appear and the
set of list names is not discoverable from the command surface.

A `todomd lists` command printing display names, and probably their directories
and task counts, closes that.
