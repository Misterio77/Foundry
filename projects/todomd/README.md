# todomd

Edit vdir-backed VTODO lists as Markdown. `todomd` renders whole lists into a
temporary document, opens an editor, previews the resulting changes, and applies
approved ones to the source `.ics` files.

The `.ics` files stay the source of truth. `todomd` does not speak CalDAV and
never runs a syncer itself; hooks pause and resume whatever does.

```console
$ todomd                  # edit every list
$ todomd edit Postgrad    # edit chosen lists
$ todomd show             # print active-root task trees as JSON
$ todomd show --completed # include every task
```

Creating, renaming, nesting, scheduling, prioritizing, completing, reopening,
moving, and deleting tasks is supported. Categories and descriptions are
preserved but not editable. Watch mode is not implemented. See
[DESIGN.md](DESIGN.md) and [ROADMAP.md](ROADMAP.md).

## Install

```console
$ nix run github:Misterio77/Foundry#todomd -- edit Postgrad
$ nix run .#todomd -- edit Postgrad
```

The Nix package installs Bash, Fish, and Zsh completions.

## Configure

`todomd` reads `$XDG_CONFIG_HOME/todomd/config.toml`, falling back to
`~/.config/todomd/config.toml`. `--config <PATH>` overrides it.

```toml
calendar_roots = ["~/Calendars/personal"]

[hooks]
before_session = [
  "systemctl", "--user", "stop",
  "vdirsyncer.timer", "vdirsyncer.service",
]
after_apply = ["systemctl", "--user", "start", "vdirsyncer.service"]
after_session = ["systemctl", "--user", "start", "vdirsyncer.timer"]
```

`calendar_roots` hold vdir collections: subdirectories of `.ics` files with a
`displayname` file whose contents are the list name. Paths support `~`.

Hooks are optional argument arrays, executed directly rather than through a
shell.

| Hook | Runs |
|---|---|
| `before_session` | Once, before any list is read. Failure aborts the command. |
| `after_apply` | Only after source files changed. Failure does not roll back, and exits non-zero. |
| `after_session` | On every exit once `before_session` succeeded: cancellation, editor failure, conflict, apply failure, and handled `SIGINT`, `SIGTERM`, `SIGHUP`. |

## Commands

| Command | Effect |
|---|---|
| `todomd` | Edit every discovered list. |
| `todomd edit [LISTS]...` | Edit the named lists, or every list. |
| `todomd show [LISTS]...` | Print tasks as JSON. |

| Option | Effect |
|---|---|
| `--config <PATH>` | Use a specific configuration file. Accepted anywhere. |
| `--completed` | Include completed and cancelled tasks. |
| `--no-hooks` | `edit` only. Skip configured hooks for this run. |
| `--keep` | `edit` only. Retain the session after an unchanged or successful run. |

Naming lists selects them and fixes their order; otherwise lists are ordered by
display name. The top level takes no list names, so a list called `show` remains
reachable as `todomd edit show`.

## Editing

`todomd` writes a private session document and opens it with `$VISUAL`, falling
back to `$EDITOR`:

```markdown
# Postgrad

- [ ] -2026-09-12 +"2026-09-07 09:00" !!! @Postgrad Paper <!-- todomd:id=t1 -->
  - [ ] -2026-09-11 ! @"Quick Win" Read related work <!-- todomd:id=t3 -->

# Personal

- [ ] Buy milk, bread <!-- todomd:id=t2 -->
```

| Edit | Result |
|---|---|
| Change task text | Rename |
| Add or change `-DATE` | Set the due date or time |
| Add or change `+DATE` | Set the start date or time |
| Remove a date marker | Clear that property |
| Add or change `!`, `!!`, `!!!` | Set priority |
| Remove the priority marker | Clear priority |
| Add or remove `@category` | Change categories |
| Change `[ ]` to `[x]` | Complete |
| Change `[x]` to `[ ]` | Reopen, with `--completed` |
| Add a `- [ ]` line without an identity | Create in that list |
| Indent a line by two spaces | Make it a child of the preceding task |
| Unindent or reindent a line | Detach or reparent it |
| Move a line or nested block under another heading | Move between lists |
| Delete a line | Delete that VTODO |
| Reorder lines | Nothing |

The `<!-- todomd:id=... -->` markers are session-local identities, not VTODO
UIDs, and track a task across renames and moves. Removing one is treated as
intentional: the old task is deleted and a new one created, which the preview
states.

Indentation edits the child's `RELATED-TO` parent. Removing a parent line
deletes only that VTODO. Retained children must be unindented or nested under
another parent. Moving a nested block moves every line in it. Empty and
dangling source relationships render as roots and remain untouched; cyclic
relationships abort the read because they cannot form a tree.

Leading fields may be entered in any order. Rerendering puts due, start,
priority, then alphabetically sorted categories before the summary. `-` means
due, `+` means start, `!!!`, `!!`, or `!` means high, medium, or low priority,
and `@name` adds a category. Quote multiword categories, as in `@"Quick Win"`.
An `@` elsewhere in the summary is ordinary text.

Date-only values render as `YYYY-MM-DD`. Datetimes render in local time as
`"YYYY-MM-DD HH:MM"`. Input additionally accepts RFC 3339 or ISO timestamps,
with or without an offset, and English expressions such as `friday`, `tomorrow
morning`, and `tonight`. Multiword values must be quoted. Relative expressions
are resolved when the edited document is read; a plain weekday includes today.
Part-of-day defaults are morning 09:00, noon 12:00, afternoon 15:00, evening
18:00, tonight 20:00, and midnight 00:00.

Datetime input is resolved to an instant and written with the machine's local
IANA `TZID`; floating source values are treated as local. Existing UTC or `TZID`
values are converted to local time for Markdown. A date paired with a datetime
is promoted to local midnight. A due value earlier than its start is rejected;
equality is allowed.

Canonical Markdown hides seconds, but unchanged markers do not rewrite source
seconds or timezone representation. Explicit seconds on changed input are
written to ICS. Fractional seconds are rejected because RFC 5545 DATE-TIME
cannot represent them. Existing `VTIMEZONE` components are preserved, but new
ones are not generated.

Each sibling set renders unfinished first, then by priority, then
alphabetically. Parents precede their recursively sorted descendants. Ordering
among siblings is presentational, so rearranging their lines changes nothing.

A summary is quoted only when its start would otherwise be read as syntax, so
ordinary text is never quoted:

| Summary | Rendered |
|---|---|
| `Write paper draft` | `- [ ] Write paper draft` |
| `He said "hi" to me` | `- [ ] He said "hi" to me` |
| `!urgent thing` | `- [ ] "!urgent thing"` |
| `@home is literal` | `- [ ] "@home is literal"` |
| `"quoted" start` | `- [ ] """quoted"" start"` |

Quote a summary yourself if you start it with `!`, `+`, `-`, `@`, or `"`, or if
it needs leading or trailing spaces. Inside quotes, write `""` for a literal `"`.

The dialect is strict. It allows selected level-one headings and `- [ ]` or
`- [x]` items indented by exactly two spaces per nesting level. Nesting may be
arbitrarily deep, but cannot skip a level. Every selected list must keep its
heading, and summaries must be single-line and non-empty.

Only active root tasks are rendered by default. Their completed subtasks remain
visible as `[x]`, but descendants below a completed subtask are hidden. A hidden
finished root therefore hides its entire subtree. `--completed` adds every
completed and cancelled tree.

`SUMMARY` is optional in iCalendar. A task without one has nothing to render, so
it and its descendant subtree are skipped in every scope and the task is
reported on stderr; edit its `.ics` directly.

After the editor exits, `todomd` rereads the sources, reconciles, and previews
both the semantic and filesystem changes:

```console
Postgrad:
  renamed   "Buy milk, bread" -> "Read related work"
  created   New task
  moved     Read related work <- Personal

Personal:
  completed Submit paper
  moved     Submit paper <- Postgrad

Files:
  move   .../Personal/groceries.ics -> .../Postgrad/groceries.ics
  create ~/Calendars/personal/Postgrad/fa62b7c0-ac46-47dd-899c-0aa6dd3f58b6.ics

Apply these changes? [y/N]
```

Only `y` or `Y` applies the plan. Anything else, including empty input, cancels
it and leaves every source file unchanged. Confirmation requires an interactive
terminal.

## Scripting

`todomd show` is read-only: no session, no editor, no hooks, no terminal.
`--completed` includes finished roots and descendants below completed subtasks.

```console
$ todomd show Personal
[
  {
    "list": "Personal",
    "uid": "f29e1dbd-b8b4-4327-89c2-608898269a01",
    "summary": "Buy milk, bread",
    "completed": false,
    "priority": "medium",
    "categories": ["Errands", "Quick Win"],
    "start": "2026-09-07 09:00",
    "due": "2026-09-12",
    "parent_uid": null,
    "file": "/home/gabriel/Calendars/personal/Personal/groceries.ics"
  }
]
```

Tasks are ordered by list and tree. Each sibling set is ordered unfinished
before finished, then by priority and summary. `completed` may be `true` in the
default scope for a subtask below active ancestors. `priority` is `none`, `low`,
`medium`, or `high`; `categories` is a sorted array of category names. `start`
and `due` use canonical local strings or `null`;
`parent_uid` is the parent VTODO UID or `null` for a rendered root.

vdir filenames are chosen by whatever created the item, so a UID cannot be
turned into a path; use `file` to read or edit an item directly.

There is no non-interactive write command. To change fields `todomd` does not
expose, edit the `.ics` at `file`, increment its `SEQUENCE`, and run the syncer.

## Safety

- Only active-root trees are rendered unless `--completed` is given. Completed
  subtasks stay visible, but traversal stops below them.
- Sources are reread after the editor exits; a source change during the session
  is reported as an inbound change or conflict instead of applying stale edits.
- Before writing, list identity, membership, and SHA-256 content hashes are
  verified, and each staged operation is rechecked immediately before it runs.
- Originals are backed up, writes use temporary files and atomic rename, and a
  mid-apply failure triggers a hash-guarded best-effort rollback.
- Patches preserve unexposed data, including `DESCRIPTION`, unrelated
  `RELATED-TO` representations, `X-` properties, and nested components such as
  `VALARM`. Unchanged categories and date properties keep their raw form.
- `PRIORITY` is written only when the marker's level changes, so a stored value
  like `4` survives edits that leave the level alone.

A multi-file change cannot be truly atomic. `todomd` never intentionally applies
part of a plan, but a crash mid-apply can leave one; the retained session and
backups support manual recovery.

## Sessions

Sessions live under `$XDG_RUNTIME_DIR/todomd/`, or a private temporary
directory.

| Artifact | Contents |
|---|---|
| `tasks.md` | The edited Markdown document. |
| `baseline.json` | The task state that was rendered. |
| `manifest.json` | Session ID to VTODO UID mapping. |
| `transactions/0001/` | Staged files, per-file backups, and `plan.json`. |

Sessions are retained, with their path printed, on rejection, invalid Markdown,
conflict, and failure. They are removed after an unchanged or successful run
unless `--keep` is given.

## Exit codes

`0` on success, including a cancelled plan. Non-zero on discovery, hook, editor,
parsing, conflict, staging, application, and post-apply failures.

## Limitations

- Active tasks only, unless `--completed` is given.
- Tasks without a summary are never rendered, only reported.
- Summaries, hierarchy, start and due dates, priority, completion, and list
  membership are the only editable fields.
- `show` reports tasks, not lists, so an empty list does not appear.
- One primary VTODO per `.ics` file.
- No CalDAV, no watch mode, no automatic crash recovery.
- Concurrency is optimistic: a source change is detected and refused, but the
  vdir is not locked. Use `before_session` to pause the syncer.
