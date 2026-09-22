# todomd

Edit vdir-backed VTODO lists as Markdown. `todomd` renders selected lists into a
private document, opens an editor, and applies each valid save to the source
`.ics` files through an LSP-backed live session.

The `.ics` files remain the source of truth. `todomd` does not speak CalDAV; an
optional hook can start a syncer after writes.

```console
$ todomd                  # edit every list
$ todomd edit Postgrad    # edit selected lists
$ todomd show             # print active tasks as JSON
$ todomd show --completed # include completed and cancelled tasks
```

Tasks can be created, renamed, nested, scheduled, prioritized, categorized,
completed, reopened, moved between lists, and deleted. Unexposed iCalendar data
such as descriptions and alarms is preserved.

## Install

```console
$ nix run github:Misterio77/Foundry#todomd -- edit Postgrad
$ nix run .#todomd -- edit Postgrad
```

The Nix package includes Bash, Fish, and Zsh completions.

## Configure

`todomd` reads `$XDG_CONFIG_HOME/todomd/config.toml`, falling back to
`~/.config/todomd/config.toml`. `--config <PATH>` overrides it.

```toml
calendar_roots = ["~/Calendars/personal"]
default_view = "default"

[views.default]
group_by = ["list"]
sort_by = ["completed", "priority", "summary"]

[views.agenda]
group_by = ["due", "list"]
sort_by = ["due", "priority", "summary"]

[views.flat]
group_by = []
sort_by = ["due", "priority", "list", "summary"]

[hooks]
after_apply = ["systemctl", "--user", "start", "vdirsyncer.service"]
```

Each `calendar_roots` entry contains vdir collection directories with `.ics`
files and a `displayname` file. Paths support `~`.

A view combines ordered `group_by` and `sort_by` keys:

| Purpose | Keys |
|---|---|
| Grouping | `list`, `completed`, `priority`, `due`, `start`, `categories` |
| Sorting | `list`, `completed`, `manual`, `due`, `start`, `priority`, `summary` |

The built-in default groups by list and sorts unfinished tasks first, then by
priority and summary. Lists follow selected-list order. Missing dates and
manual ranks sort last; a specific time sorts before the all-day value on the
same date. Task identity is the final deterministic tie-breaker. `manual` reads
`X-APPLE-SORT-ORDER`, but Markdown reordering does not write it.

`after_apply` runs directly after a successful source transaction. Failure is
reported through LSP without rolling back the already-applied transaction.

## Commands

| Command or option | Effect |
|---|---|
| `todomd` | Edit every discovered list. |
| `todomd edit [LISTS]...` | Edit selected lists, or every list. |
| `todomd show [LISTS]...` | Print tasks as JSON. |
| `todomd session create [LISTS]...` | Create a reusable manual session. |
| `todomd session apply <SESSION>` | Apply and canonicalize a manual session. |
| `todomd session close [--force] <SESSION>` | Remove a session. |
| `todomd lsp` | Run the language server. |
| `--config <PATH>` | Use another configuration file. |
| `--completed` | Include completed and cancelled trees. |
| `--view <NAME>` | Select a named view. |
| `--group-by <KEYS>` | Override grouping with comma-separated keys. |
| `--no-group` | Render without group headings. |
| `--sort-by <KEYS>` | Override sorting with comma-separated keys. |
| `--no-hooks` | Skip `after_apply` for this edit session. |

Explicit grouping and sorting overrides take precedence over `--view`, then the
configured default. Naming lists selects and orders them; use `todomd edit show`
to edit a list literally named `show`.

## Edit Markdown

The default view looks like this:

```markdown
# Postgrad

- [ ] -2026-09-12 +"2026-09-07 09:00" !!! [Research] Paper <!--t1-->
  - [ ] -2026-09-11 ! ["Quick Win"] Read related work <!--t3-->

# Personal

- [ ] Buy milk <!--t2-->
```

Task fields are:

| Syntax | Meaning |
|---|---|
| `[ ]` / `[x]` | Active or completed |
| `@Postgrad` | List, on roots when not supplied by grouping |
| `-2026-09-12` | Due date or time |
| `+"2026-09-07 09:00"` | Start date or time |
| `!`, `!!`, `!!!` | Low, medium, or high priority |
| `[Research, "Quick Win"]` | Complete category set |
| `<!--t1-->` | Session-local task identity |

Leading fields may appear in any order; canonical rendering restores list,
due, start, priority, categories, then summary. Quote marker values containing
spaces by doubling embedded quotes. Quote a summary when it begins with syntax
(`!`, `+`, `-`, `@`, `[`, or `"`), has edge whitespace, or ends with an
identity-shaped comment.

Common edits:

| Edit | Result |
|---|---|
| Change summary or field markers | Update task fields. |
| Change `[ ]` to `[x]`, or back | Complete or reopen; use `--completed` to load old completed tasks. |
| Add an identity-free task | Create a VTODO. |
| Delete a task line | Delete that VTODO. |
| Indent by two spaces | Make it a child of the preceding task. |
| Reindent or unindent | Reparent or detach it. |
| Move a root beneath another grouping heading | Change the grouped field. |
| Add an explicit root marker | Override a conflicting heading. |
| Reorder lines within one group | No semantic change. |

Removing an identity marker means delete the old task and create a new one.
Only trailing comments exactly shaped like `<!--tN-->` are identities; other
HTML comments belong to the summary.

### Group headings are editable

Grouping headings supply omitted fields to roots. For example:

```toml
group_by = ["due", "list", "priority"]
```

```markdown
# 2026-09-22

## Magalu

### High priority

- [ ] Executar CR <!--t1-->
```

The root inherits due date `2026-09-22`, list `Magalu`, and high priority.
Moving it beneath another valid heading changes that field. A conflicting
explicit marker such as `@Personal`, `-2026-09-23`, or `!` wins and causes the
task to regroup after save.

Only roots inherit headings because groups describe whole trees. Descendants
retain their own markers and always inherit their parent's list. Completion is
always controlled by `[ ]` / `[x]`. Unknown list names, malformed dates or
category sets, and invalid fixed labels are rejected.

With no grouping, roots render every field explicitly. When grouped by list,
roots omit `@list`; when grouped by due, start, priority, or categories, they
omit that corresponding marker. Missing values use headings such as `No due
date` and `No categories`.

A vdir `color` file containing `#RRGGBB` is exposed through LSP for list-group
headings. Helix 25.07 and newer can show the color inline.

### Trees and dates

A root and all descendants stay together for grouping and top-level ordering.
Sibling sets are sorted recursively; parents always precede descendants.
Category grouping uses the complete set as one value rather than duplicating a
task into several groups.

Indentation writes `RELATED-TO;RELTYPE=PARENT`. Descendants cannot carry
`@list`; moving a root moves its whole tree. Dangling source relationships
render as roots, while cycles abort loading.

Dates accept `YYYY-MM-DD`, local datetimes, ISO/RFC 3339 timestamps, and English
expressions such as `friday`, `tomorrow morning`, and `tonight`. Datetimes render
as `"YYYY-MM-DD HH:MM"` in local time. Relative expressions resolve when the
document is read. A date paired with a datetime is promoted to local midnight;
due must not precede start.

Canonical Markdown hides seconds without rewriting unchanged source precision
or timezone representation. Fractional seconds are unsupported by RFC 5545
DATE-TIME and are rejected.

## Editor-independent sessions

The explicit session lifecycle works without an editor integration or LSP:

```console
$ session=$(todomd session create Postgrad Personal)
$ hx "$session/tasks.md"
$ todomd session apply "$session"
$ todomd session close "$session"
```

`create` accepts the same list, scope, view, and `--no-hooks` options as `edit`.
It persists the resolved configuration and prints only the session directory to
stdout; warnings go to stderr.

`apply` parses `tasks.md`, rereads ICS, and uses the same reconciliation,
conflict detection, transaction, rollback, and hook machinery as live editing.
It then rewrites `tasks.md` canonically, advances the session baseline, and
keeps the session available for another edit/apply cycle. An ICS-only change is
accepted as an inbound refresh. Errors and conflicts preserve the session.

`close` removes a session only when `tasks.md` matches `accepted.md`, preventing
accidental loss of unapplied edits. `--force` discards them intentionally.
Apply, close, and live LSP access are protected by an exclusive session lock.

## Live editing

`todomd edit` requires the editor to attach `todomd lsp` as a Markdown language
server. It fails rather than silently discarding edits if attachment does not
happen within ten seconds.

Helix configuration:

```toml
[language-server.todomd]
command = "todomd"
args = ["lsp"]

[[language]]
name = "markdown"
language-servers = ["marksman", "todomd"]
```

Each valid save applies its semantic transaction and replaces the buffer with
canonical Markdown. Invalid buffers receive line diagnostics. Source-side ICS
changes refresh a clean buffer; simultaneous Markdown and ICS changes produce a
conflict instead of overwriting either side. Tasks completed during an active
session remain visible so they can be reopened.

`todomd.changeView` switches the open session's view without touching ICS or
running hooks. Supporting clients show a picker; clients such as Helix that do
not implement `window/showMessageRequest` cycle to the next view. The buffer
must match its last accepted canonical text.

Helix shows an LSP spinner by default. To display progress text too:

```toml
[editor.lsp]
display-progress-messages = true
```

## Scripting

`todomd show` is read-only: it creates no session, opens no editor, and runs no
hooks. Tasks follow the active view's group and tree order, but JSON contains no
heading objects.

```console
$ todomd show Personal
[
  {
    "list": "Personal",
    "uid": "f29e1dbd-b8b4-4327-89c2-608898269a01",
    "summary": "Buy milk",
    "completed": false,
    "priority": "medium",
    "categories": ["Errands"],
    "start": "2026-09-07 09:00",
    "due": "2026-09-12",
    "parent_uid": null,
    "file": "/home/gabriel/Calendars/personal/Personal/groceries.ics"
  }
]
```

Use `file` to locate a VTODO; vdir filenames are not derived from UIDs.
`session apply` is the scriptable write boundary, but it consumes session
Markdown rather than JSON patches. For unsupported fields, edit the `.ics`,
increment `SEQUENCE`, and run the syncer.

## Safety and recovery

- Active-root trees are shown unless `--completed` is given. Completed subtasks
  stay visible, but traversal stops below them.
- Source identity, membership, and SHA-256 hashes are checked before and during
  writes. Concurrent source changes become inbound refreshes or conflicts.
- Writes use temporary files and atomic rename. Originals are backed up, and a
  partial failure triggers a hash-guarded best-effort rollback.
- Patches preserve unexposed properties, nested components, and unchanged raw
  representations. Priority is written only when its displayed level changes.
- A multi-file update cannot be truly atomic; retained sessions, plans, and
  backups support manual recovery after a crash.

Sessions live under `$XDG_RUNTIME_DIR/todomd/`, or a private temporary directory:

| Artifact | Contents |
|---|---|
| `.todomd-session`, `.lock` | Session marker and exclusive lifecycle lock. |
| `tasks.md` | Edited Markdown. |
| `baseline.json` | Rendered task state. |
| `manifest.json` | Session identity to VTODO UID mapping. |
| `accepted.md` | Last accepted canonical document. |
| `live.json` | Resolved config, lists, scope, and active view. |
| `unaccepted.md` | Unapplied contents retained on close. |
| `transactions/0001/` | Plan, staged files, and backups. |

## Limitations

- Active tasks only unless `--completed` is given.
- Tasks without summaries are reported but not rendered.
- Editable fields are summary, hierarchy, list, completion, priority,
  categories, start, and due.
- One primary VTODO per `.ics` file.
- Empty lists do not appear in `show`.
- Live editing requires versioned LSP workspace edits.
- No CalDAV, vdir lock, direct JSON writes, or automatic crash recovery.

See [DESIGN.md](DESIGN.md) for invariants and internals, and
[ROADMAP.md](ROADMAP.md) for planned work.
