# todomd design

## Goal

Edit local, vdir-backed VTODO lists through a temporary Markdown document. A
user selects whole lists, edits their tasks, reviews the resulting semantic
change plan, and applies it to the source `.ics` files.

The `.ics` files are the source of truth. Markdown is a session-scoped editing
surface, not a second task store. `todomd` does not speak CalDAV; synchronizing
the vdirs is an independent concern reached through hooks.

An LSP-backed live driver validates while typing, applies valid saves, and
synchronizes source changes into the editor buffer.

## Scope

Supported:

- selecting whole lists by display name;
- creating, renaming, nesting, scheduling, prioritizing, completing, reopening,
  moving, and deleting tasks;
- preserving iCalendar data the Markdown does not expose;
- detecting source changes made during a session;
- staging, backup, and best-effort rollback;
- an optional hook after each apply;
- a read-only JSON view; and
- live diagnostics and bidirectional editor synchronization through LSP.

Not supported:

- CalDAV, or controlling synchronization software directly;
- editing descriptions, recurrence, or alarms;
- persistent task ordering;
- silently merging concurrent semantic edits; or
- general-purpose iCalendar editing.

Deferred: automatic crash recovery and richer language features beyond the
editing lifecycle.

## Principles

1. **Model tasks, not files.** Plans describe each task's before and after state
   independently of source paths.
2. **Preserve what is not exposed.** Editing a summary must not discard an
   alarm, recurrence rule, relationship, or vendor property.
3. **Plan before mutation.** Parsing, validation, reconciliation, and staging
   finish before any source file changes.
4. **Treat concurrency as normal.** Every transaction compares both sides
   against a last-agreed baseline.
5. **Keep the driver thin.** Saves and filesystem events trigger transactions;
   the driver contains no synchronization logic.
6. **Assume repeated transactions.** The core never assumes one parse or apply
   cycle per session.
7. **Keep the open buffer authoritative.** Editing never replaces the session
   document behind the editor; canonical and inbound changes use versioned LSP
   workspace edits.
8. **Reject ambiguity.** Invalid Markdown, unknown identities, duplicate lists,
   and concurrent edits stop the transaction.

## Architecture

```text
                 ┌──────────────────────┐
ICS repository ─▶│                      │
                 │   canonical model    │
Markdown codec ─▶│                      │
                 └──────────┬───────────┘
                            │
                 baseline / Markdown / ICS
                            │
                            ▼
                    reconciliation planner
                            │
                         change set
                            │
                  validation and staging
                            │
                            ▼
                         applier

LSP live driver ─── trigger the transaction engine
```

| Component | Responsibility |
|---|---|
| Canonical model | Editable meaning only: list identity, task identity, parent identity, list membership, summary, start and due values, completion state |
| Source snapshot | Patch context: source paths, raw file hashes, parsed objects, unexposed properties |
| ICS repository | Discovers lists, reads VTODOs, patches objects, stages and applies filesystem operations |
| Markdown codec | Deterministic rendering and strict parsing |
| Reconciliation planner | Classifies divergence and produces a change set |
| Transaction engine | Validates, stages, applies, and advances the baseline |
| Driver | Owns interaction and event policy |
| LSP adapter | Tracks open-buffer versions, publishes diagnostics, and requests canonical workspace edits |

The canonical model holds no paths, raw files, parsed iCalendar objects, editor
state, or language-server state, which keeps baselines and planning
format-independent.
The source snapshot carries that material separately, so raw hashes can guard
application against changes the model and Markdown do not represent.

Module layout follows this split: `config`, `model`, and `repository` are
shared; each subcommand is a directory, with the editing machinery under
`edit/`.

## Commands

Modes are subcommands, so each carries only the options that apply to it.
Editing is always an LSP-backed live session.

| Command | Effect |
|---|---|
| `todomd` | Edit every discovered list |
| `todomd edit [LISTS]...` | Edit the named lists, with optional `--no-hooks` |
| `todomd show [LISTS]...` | Print tasks as JSON |
| `todomd lsp` | Run the language server over standard input/output for editor integration |

Both subcommands take `--completed`, which widens the task set from active-root
trees to every task.

Lists are positional only inside a subcommand. The top level takes no list
arguments, so a list sharing a subcommand's name stays addressable and an
unknown verb is reported rather than read as a list name.

Omitting list names selects every discovered list, ordered by display name. A
command resolves that set once and reuses it, so a list appearing mid-session
cannot become a spurious inbound change.

`show` is the read surface for scripts and agents. It emits a JSON array of
tasks, each with its list, UID, summary, completion flag, priority, canonical
start and due values, rendered parent UID, and absolute source file. It performs
no session, editor, hook, or terminal work. The file is required because vdir
item filenames are chosen by whatever created them, so a UID cannot be mapped
to a path without reading the collection.

`show` has no write counterpart. Fields the Markdown does not expose are edited
in the `.ics` directly, which suits both scripts and a deliberately narrow
Markdown dialect.

## List discovery

Configuration holds one or more vdir roots. Immediate child directories are
candidate lists, matched by the content of their `displayname` file rather than
their directory name.

Missing names, duplicate display names, unreadable lists, and malformed VTODO
files are reported before the document opens. A file is never silently omitted
from a selected list: parse failures abort, and valid tasks that cannot be
rendered are reported.

One primary VTODO per `.ics` file is supported. Auxiliary components in the file
are preserved.

## Task scope

A command operates on active root trees or, with `--completed`, on every task.
Completed and cancelled tasks are one set, and both render as `[x]`. The default
scope includes a finished subtask when all of its ancestors are active, then
stops before that subtask's descendants. A finished root therefore hides its
full descendant subtree, and a task never appears without its parent.

The scope is resolved once and reused for the initial read, the reread after the
editor exits, and the accepted-state refresh. Reading a different set at any of
those points would turn tasks outside the scope into phantom deletions.

`SUMMARY` is optional in RFC 5545, so a task without one is valid but has no
Markdown representation. Such a task and its descendant subtree are excluded
from every scope, regardless of completion, and the task is reported on stderr
rather than failing the command or vanishing silently. They stay editable
through their `.ics` files.

Status is never rewritten unless the checkbox changes, so a cancelled task keeps
its status unless it is explicitly reopened.

## Markdown format

```markdown
# Postgrad

- [ ] -2026-09-12 +"2026-09-07 09:00" !!! @Postgrad Paper <!--t1-->
  - [ ] -2026-09-11 @"Quick Win" Email advisor

# Personal

- [ ] ! Buy groceries <!--t3-->
```

A task line is a checkbox, optional due (`-`) and start (`+`) fields, an
optional priority marker, zero or more category markers (`@name`), a summary,
and an optional identity marker. Input fields may appear in any order; rendering
canonicalizes them to due, start, priority, then alphabetically sorted
categories. Multiword categories use the same doubled-quote form as other
fields, such as `@"Quick Win"`. Category markers are recognized only among the
leading fields, so an `@` inside a summary is literal. Empty `CATEGORIES`
properties emitted by other clients represent an empty set and are ignored;
multiline category values cannot be represented and abort the read.

Within each sibling set, tasks follow the configured sort keys. The default is
unfinished first, then descending priority, then case-insensitive summary.
Available keys are completion, manual `X-APPLE-SORT-ORDER`, due date, start date,
priority, and summary; individual lists may replace the default key sequence.
Missing manual and date values sort last, and task identity always breaks final
ties. A parent precedes its recursively sorted descendants, so the same state
always renders identically. Sorting finished siblings last by default keeps the
wider scope usable when a list holds one open task among hundreds.

Sibling ordering carries no editable meaning yet: reordering lines is not a
change, and the manual key only reads values written by other clients.
Indentation alone carries hierarchy. Because Markdown flattens nine iCalendar
priorities into three levels, sibling tasks stored as `PRIORITY:1` and
`PRIORITY:4` interleave according to later keys.

Each selected list appears exactly once as a level-one heading. Existing tasks
carry opaque, session-local IDs mapped to source identities by the manifest.
Session IDs rather than raw VTODO UIDs avoid leaking or misparsing arbitrary UID
contents. A task without an ID is new.

Markers render as `<!--t1-->`. The editor cannot be asked to hide buffer text,
since LSP can add or recolor but never subtract, so the marker is kept short
enough to ignore instead. Only a trailing comment whose body is a session
identity, `t` followed by digits, is reserved; any other trailing HTML comment,
and an identity-shaped one anywhere but the end of the line, is summary text.
A summary that would itself end in one is quoted, which moves the line's final
`-->` inside the quotes and leaves the real marker last.

In the default scope active roots and their descendants render. Completed
subtasks render checked, and traversal stops below them. Tasks outside the
current scope are absent from the document, so their absence is never read as
deletion. A task completed by the current live session remains in its active-scope
document for the rest of the session, allowing an immediate reopen. An unchanged
`IN-PROCESS` task stays `IN-PROCESS`; unchecked syntax
alone does not normalize it to `NEEDS-ACTION`.

| Markdown edit | Operation |
|---|---|
| Change task text | Rename |
| Add or change `-DATE` | Set the due date or datetime |
| Add or change `+DATE` | Set the start date or datetime |
| Remove a date field | Clear that property |
| Add or change `!`, `!!`, `!!!` | Set priority |
| Remove the priority marker | Clear priority |
| Add or remove `@category` | Change the category set |
| Change `[ ]` to `[x]` | Complete |
| Change `[x]` to `[ ]` | Reopen |
| Add an item without an ID | Create in the containing list |
| Indent an item | Set its parent to the preceding item one level up |
| Unindent or reindent an item | Detach or reparent it |
| Move an item or nested block under another heading | Move those tasks to that list |
| Remove an identified item | Delete that VTODO only |
| Reorder siblings | No change |

Task-list items use exactly two spaces per nesting level and may nest to
arbitrary depth. A task cannot skip a level or have a parent in another list.
Blank lines are insignificant. Additional headings, missing or renamed selected
headings, duplicate or unknown IDs, malformed indentation or checkboxes, empty
summaries, duplicate fields, and unsupported Markdown are parse errors.

Deleting a parent line deletes only that VTODO. Removing its nested block also
deletes each child line; retaining and unindenting a child explicitly detaches
it. Moving a nested block moves every represented task. Completion is
independent of hierarchy, so a parent may be completed while children remain
open.

### Quoting

A summary is quoted only when reading it back would otherwise be ambiguous: when
it starts with `!`, `+`, `-`, `@`, or `"`, or when leading or trailing whitespace
would be lost.
Inside quotes a literal `"` is doubled, so the dialect needs no second escape
character.

The summary's right edge is delimited by the identity marker, so only its first
character and a trailing identity-shaped comment can be ambiguous. Interior
quotes are therefore left alone and ordinary prose never acquires quoting. An
unquoted summary that starts with a reserved character is a parse error rather
than a guess, and an unquoted trailing marker is the task's identity rather than
text.

This generalizes: fields added later can reserve leading or trailing syntax
without inventing their own escape.

New tasks receive draft identities in document order during parsing. Parent
references may name either an existing task or an earlier draft at the preceding
indentation level. Planning allocates every new VTODO UID before staging any
file, so arbitrarily nested new trees can be written in any plan order. After a
successful apply, the canonical rendering is sent back as a versioned workspace
edit with session IDs, so a later transaction cannot mistake a task for another
creation. The editor reports that document change back to the server.

## Reconciliation

The planner receives three semantic states: the **baseline** last known to agree
on both sides, the parsed **Markdown**, and a fresh read of the selected
**ICS** lists.

| Markdown vs baseline | ICS vs baseline | Classification |
|---|---|---|
| unchanged | unchanged | no change |
| changed | unchanged | Markdown-to-ICS plan |
| unchanged | changed | ICS-to-Markdown update |
| changed | changed | conflict |

The live driver applies Markdown-to-ICS plans on save and consumes
ICS-to-Markdown updates from source events. Semantic changes on both sides are a
conflict even when they appear unrelated.
Per-task merging could be added later without changing the planner's inputs.

A raw ICS change that alters no editable semantics refreshes source metadata
only. It must not force a Markdown rewrite, and an outgoing apply may proceed
only against the refreshed source object.

## Transactions

A transaction is callable without an editor process. It:

1. reads the Markdown document and the selected vdirs;
2. parses both into canonical states;
3. reconciles them against the baseline;
4. validates the result and builds a semantic change set;
5. stages every filesystem operation;
6. treats the explicit save as approval;
7. applies the stage;
8. rerenders accepted Markdown when identities were added or changed;
9. advances the baseline and source snapshot; and
10. runs any post-apply hook.

A failure before application leaves the previous baseline valid. A post-apply
hook failure does not undo valid local changes or their new baseline. In live
mode, source application and accepted-state persistence precede the canonical
workspace edit. Source-side reconciliation and configured `after_apply` hooks
are exposed through LSP work-done progress when the client supports it. If the
client rejects the canonical edit, the server reports the failure and waits for
a refresh rather than guessing at buffer state.

### Application safety

Each initial read records the membership and raw content hashes of every file in
the selected lists, including data absent from Markdown. Immediately before
application, the applier rechecks that list identity, membership, and all raw
hashes still match the snapshot the stage was built from, and rechecks each
operation's own inputs before running it.

Replacements are written to temporary files on the destination filesystem and
renamed into place. Originals are copied into the transaction's `backup/`
directory before being replaced, moved, or deleted. Moves keep the source
filename; a destination collision fails the transaction rather than overwriting.

A change spanning several files cannot be truly atomic. If an operation fails
after mutation begins, `todomd` rolls back under the same hash guards, retains
the session, and reports both the original and rollback failures. It never
intentionally applies part of a plan. Process or machine failure can still
interrupt rollback; the retained stage and backups support manual recovery, but
automatic crash recovery is not claimed.

Hash checks reduce but cannot eliminate a race with an uncooperative concurrent
writer. Editing relies on short transactions, fresh reads, and explicit
conflict handling.

### Session storage

Sessions are private `0700` directories below `$XDG_RUNTIME_DIR/todomd`, falling
back to the system temporary directory:

```text
session-XXXXXX/
├── tasks.md
├── manifest.json
├── baseline.json
├── accepted.md
├── recovery-baseline.json
├── live.json
├── unaccepted.md            # only when closing with unapplied buffer edits
└── transactions/
    └── 0001/
        ├── plan.json
        ├── staged/
        └── backup/
```

Numbering supports repeated transactions. Session metadata records the resolved
configuration, selected lists, scope, and hook policy so an independently
spawned language server can attach safely. Sessions are retained on close, and
`unaccepted.md` preserves buffer contents that did not become an accepted
transaction. Backups contain task data and inherit the private permissions.

## Approval and errors

A save is explicit approval to apply a valid Markdown-to-ICS plan. Invalid
Markdown, source failures, conflicts, and post-apply hook failures are reported
through diagnostics and LSP messages without ending the editor session. Setup,
attachment, editor, and handled termination failures exit non-zero. Signals
that cannot be handled, notably `SIGKILL`, cannot promise cleanup.

## iCalendar handling

Existing files are patched, never rebuilt from Markdown fields, preserving:

- unchanged due, start, and category representations;
- descriptions;
- alarms and recurrence;
- unchanged `RELATED-TO` representations;
- time zone components; and
- vendor-specific properties.

Files untouched by a change set are not rewritten. Patched components are
serialized through a typed writer so edited `TEXT` values are escaped.

Changing an existing task increments `SEQUENCE` and updates `DTSTAMP` and
`LAST-MODIFIED`. Completion sets `STATUS`, `COMPLETED`, and `PERCENT-COMPLETE`
consistently; reopening sets `STATUS` to `NEEDS-ACTION` and removes `COMPLETED`
and `PERCENT-COMPLETE`. Source filenames and VTODO UIDs are independent
identities.

Date-only fields render as `YYYY-MM-DD`; datetimes render as quoted local
`"YYYY-MM-DD HH:MM"`. Parsing also accepts ISO/RFC 3339 timestamps and English
relative expressions. Zoned and UTC source values are converted to the local
IANA timezone, while floating values are interpreted there. Writes use
`VALUE=DATE` or a local `TZID` datetime and do not generate `VTIMEZONE`.

The canonical datetime hides seconds. A date property is written only when its
rendered value changes, so untouched seconds, zones, floating values, and
parameters survive unrelated edits. Changed input keeps whole seconds;
fractional seconds are rejected because RFC 5545 cannot represent them. Mixed
DATE and DATE-TIME pairs promote the date side to local midnight. Planning
rejects due before start but permits equality and preserves an untouched invalid
source pair.

`RELATED-TO` without `RELTYPE`, and `RELATED-TO;RELTYPE=PARENT`, both name a
parent when read. Writing always emits the explicit
`RELATED-TO;RELTYPE=PARENT` form, because the default relationship type is only
implied by RFC 5545 and clients such as todoman do not read a bare `RELATED-TO`
as a parent. Other relationship types are preserved but do not affect
indentation. Empty and dangling values render as roots and stay untouched unless
the item is reindented. Identical duplicate parent properties are accepted and
preserved through unrelated edits; conflicting values and relationship cycles
abort the read. An explicit relationship change replaces every parent property
with the canonical one, or removes them.

A task whose parent is unchanged keeps its stored representation, so bare
parent properties written by todomd or another client are normalized only when
that task is reparented.

`CATEGORIES` properties and comma-separated category lists read as one sorted,
deduplicated set. A category is written only when that set changes, so untouched
property count, ordering, parameters, and escaping survive unrelated edits.
Changed categories are written canonically as one escaped `CATEGORIES` property
per value; removing every marker clears the properties.

`PRIORITY` is 1-9 in iCalendar but three levels in Markdown: 1-4 read as `!!!`,
5 as `!!`, 6-9 as `!`, and anything absent or out of range as no marker. A value
is written only when the level changes, so a task stored as `PRIORITY:4` keeps
that value through edits that leave its marker alone. Clearing the marker
removes the property; setting one writes the canonical 1, 5, or 9.

## Hooks

Configuration lives at `$XDG_CONFIG_HOME/todomd/config.toml`, falling back to
`~/.config/todomd/config.toml`. Paths support home-directory expansion.
`sorting.default` configures sibling sorting, while `sorting.lists` contains
per-display-name replacements. Omitting it preserves the completion, priority,
summary default. `manual` reads an integer `X-APPLE-SORT-ORDER`; malformed
values fail only lists configured to use that key, while missing values sort
last.

`after_apply` is an optional argument array executed directly after each
successful outgoing transaction. Its failure is reported but does not roll back
valid source changes. It is the only hook, and unknown `[hooks]` keys are
rejected so a configuration written for a removed session-lifetime hook fails
loudly instead of silently doing nothing.

## LSP-backed editing

`edit` creates a live session and opens its Markdown document. The
editor starts `todomd lsp` as a secondary Markdown language server; the server
recognizes todomd session documents from their private sidecar metadata and
ignores ordinary Markdown. A short attachment handshake prevents editing from
silently running without LSP support.

The server keeps the editor's current text and version in memory. `didOpen` and
`didChange` parse without touching source files and publish line-scoped
diagnostics. `didSave` rereads the selected vdirs, reconciles against the last
accepted baseline, and treats a valid Markdown-to-ICS plan as approved. It
stages and applies the transaction, persists the new baseline and manifest,
runs `after_apply`, and requests a versioned whole-document edit containing the
canonical rendering. The workspace edit may leave the buffer modified, but it
does not require a reload and cannot silently replace newer editor contents.

The server watches selected list directories rather than existing files,
because synchronization tools commonly save by temporary-file rename. Relevant
events are debounced and reconciled against the in-memory buffer. An ICS-only
change becomes a versioned workspace edit. If the buffer also changed, neither
side is modified and a conflict diagnostic remains until one side returns to
the accepted state.

Diagnostics carry precise line ranges when the Markdown parser can identify a
line. Save, apply, inbound-refresh, hook, and conflict state use standard LSP
messages rather than terminal output. Routine success is informational;
loading source-side ICS changes and running an `after_apply` hook additionally
use work-done progress. Errors and conflicts remain visible as diagnostics until
resolved.

The language server may serve multiple documents, but each live session has one
owning document and source watcher. Closing it stops that watcher and leaves the
private session and numbered transaction artifacts available for recovery.

## Deferred decisions

- compatibility rules for recurring VTODOs and unusual multi-component files;
- session manifest migration policy;
- durable crash-recovery protocol;
- live-mode conflict and recovery code actions;
- completion, hover, and document-symbol support;
- whether clients should be offered optional automatic saving after canonical edits; and
- whether per-task merging is worthwhile.
