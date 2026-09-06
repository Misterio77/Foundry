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

## Subtasks

VTODO relates a child to its parent through `RELATED-TO`. `todomd` preserves the
property but renders every task flat, so hierarchy is invisible and nothing
stops a parent from being deleted while its children survive.

What the real vdirs contain:

- 201 tasks carry `RELATED-TO`, and nesting is one level deep throughout;
- 47 carry an empty `RELATED-TO:`, which must read as no parent;
- 4 name a parent that is not present;
- no parent and child live in different lists; and
- both `RELATED-TO:` and `RELATED-TO;RELTYPE=PARENT:` appear, the bare form
  meaning the same thing.

Nested list items are the obvious rendering, which reverses the current rule
that only top-level items are editable. Ordering becomes partly structural too,
since tasks sort by summary today but children have to follow their parent.

Decisions needed: what deleting a parent does to its children, whether a parent
can be completed while children are open, and whether a child may move to a list
its parent is not in. An empty or dangling parent reference must render as a
top-level task rather than an error.

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
