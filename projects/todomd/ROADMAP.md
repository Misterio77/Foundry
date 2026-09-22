# todomd roadmap

Planned work, most valuable first. [DESIGN.md](DESIGN.md) holds the design these
build on.

## Explicit session lifecycle

Add editor-independent primitives for creating, applying, and closing sessions:

```console
todomd session create [LISTS]...
todomd session apply <SESSION>
todomd session close [--force] <SESSION>
```

`create` should resolve configuration, scope, lists, and view; persist the same
private artifacts used by live editing; and print only the session directory to
stdout. It must not launch an editor or require LSP, so callers can compose it
with any editor or script.

`apply` should parse `tasks.md`, reread ICS, run the existing three-way
reconciliation and transaction machinery, rewrite canonical Markdown, and
advance `baseline.json` and `accepted.md`. It always keeps the session for
another edit/apply cycle. Validation errors, source conflicts, and write
failures likewise retain every artifact for recovery.

`close` is the explicit terminal step. It should compare `tasks.md` with
`accepted.md`, refuse to discard unapplied byte changes, and allow intentional
discard through `--force`.

Build these commands on shared internal operations for selection, repository
loading, scope, view resolution, and projection. A future
`session edit --lsp/--no-lsp` can let top-level `edit` become a convenience
orchestrator over the same lifecycle. A future `session refresh` can accept inbound
ICS state. `show` should share the load/project core while continuing to emit
JSON without creating a runtime session.

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
