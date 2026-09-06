# todomd

Edit vdir-backed VTODO lists as Markdown. `todomd` renders whole lists into a
temporary document, opens an editor, previews the resulting changes, and applies
approved ones to the source `.ics` files.

The `.ics` files stay the source of truth. `todomd` does not speak CalDAV and
never runs a syncer itself; hooks pause and resume whatever does.

```console
$ todomd                  # edit every list
$ todomd edit Postgrad    # edit chosen lists
$ todomd show             # print active tasks as JSON
$ todomd show --completed # include finished tasks
```

Creating, renaming, completing, reopening, moving, and deleting tasks is
supported. Due dates, priorities, categories, and descriptions are preserved but
not editable. Watch mode is not implemented. See [DESIGN.md](DESIGN.md) and
[ROADMAP.md](ROADMAP.md).

## Install

```console
$ nix run github:Misterio77/Foundry#todomd -- edit Postgrad
$ nix run .#todomd -- edit Postgrad
```

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

- [ ] Write paper draft <!-- todomd:id=t1 -->
- [ ] Read related work <!-- todomd:id=t3 -->

# Personal

- [ ] Buy milk, bread <!-- todomd:id=t2 -->
```

| Edit | Result |
|---|---|
| Change task text | Rename |
| Change `[ ]` to `[x]` | Complete |
| Change `[x]` to `[ ]` | Reopen, with `--completed` |
| Add a `- [ ]` line without a marker | Create in that list |
| Move a line under another heading | Move between lists |
| Delete a line | Delete |
| Reorder lines | Nothing |

The `<!-- todomd:id=... -->` markers are session-local identities, not VTODO
UIDs, and track a task across renames and moves. Removing one is treated as
intentional: the old task is deleted and a new one created, which the preview
states.

The dialect is strict. Only the selected level-one headings and top-level
`- [ ]` and `- [x]` items are allowed, every selected list must keep its
heading, and summaries must be single-line and non-empty.

Only active tasks are rendered by default, so finished history is neither shown
nor touched. `--completed` adds completed and cancelled tasks as `[x]` lines,
making them editable: unticking one reopens it, and deleting its line deletes
it.

`SUMMARY` is optional in iCalendar. A task without one has nothing to render, so
it is skipped in every scope and reported on stderr; edit its `.ics` directly.

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
  move   ~/Calendars/personal/Personal/groceries.ics -> ~/Calendars/personal/Postgrad/groceries.ics
  create ~/Calendars/personal/Postgrad/fa62b7c0-ac46-47dd-899c-0aa6dd3f58b6.ics

Apply these changes? [y/N]
```

Only `y` or `Y` applies the plan. Anything else, including empty input, cancels
it and leaves every source file unchanged. Confirmation requires an interactive
terminal.

## Scripting

`todomd show` is read-only: no session, no editor, no hooks, no terminal.
`--completed` includes finished tasks.

```console
$ todomd show Personal
[
  {
    "list": "Personal",
    "uid": "f29e1dbd-b8b4-4327-89c2-608898269a01",
    "summary": "Buy milk, bread",
    "completed": false,
    "file": "/home/gabriel/Calendars/personal/Personal/groceries.ics"
  }
]
```

Tasks are ordered by list, then summary. `completed` is `true` only for tasks
revealed by `--completed`.

vdir filenames are chosen by whatever created the item, so a UID cannot be
turned into a path; use `file` to read or edit an item directly.

There is no non-interactive write command. To change fields `todomd` does not
expose, edit the `.ics` at `file`, increment its `SEQUENCE`, and run the syncer.

## Safety

- Only active tasks are rendered unless `--completed` is given, so finished
  history is not disturbed by default.
- Sources are reread after the editor exits; a source change during the session
  is reported as an inbound change or conflict instead of applying stale edits.
- Before writing, list identity, membership, and SHA-256 content hashes are
  verified, and each staged operation is rechecked immediately before it runs.
- Originals are backed up, writes use temporary files and atomic rename, and a
  mid-apply failure triggers a hash-guarded best-effort rollback.
- Patches preserve unexposed data, including `DUE`, `PRIORITY`, `CATEGORIES`,
  `DESCRIPTION`, `RELATED-TO`, `X-` properties, and nested components such as
  `VALARM`.

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
- Summaries, completion, and list membership are the only editable fields.
- `show` reports tasks, not lists, so an empty list does not appear.
- One primary VTODO per `.ics` file.
- No CalDAV, no watch mode, no automatic crash recovery.
- Concurrency is optimistic: a source change is detected and refused, but the
  vdir is not locked. Use `before_session` to pause the syncer.
