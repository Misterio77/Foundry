# todomd

Edit vdir-backed VTODO lists as Markdown. `todomd` renders whole lists into a
private document, opens an editor, and applies each valid save to the source
`.ics` files through an LSP-backed live session.

The `.ics` files stay the source of truth. `todomd` does not speak CalDAV or run
a syncer itself; an optional hook can start one after changes are applied.

```console
$ todomd                  # edit every list
$ todomd edit Postgrad    # edit chosen lists
$ todomd show             # print active-root task trees as JSON
$ todomd show --completed # include every task
```

Creating, renaming, nesting, scheduling, prioritizing, completing, reopening,
moving, and deleting tasks is supported. Categories are editable; descriptions
are preserved. See
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

[sorting]
default = ["completed", "priority", "summary"]

[sorting.lists]
Postgrad = ["manual", "due", "summary"]

[hooks]
after_apply = ["systemctl", "--user", "start", "vdirsyncer.service"]
```

`calendar_roots` hold vdir collections: subdirectories of `.ics` files with a
`displayname` file whose contents are the list name. Paths support `~`.

`sorting.default` sets the sibling sort keys, and entries under
`sorting.lists` replace it for named lists. Available keys are `completed`
(unfinished first), `manual` (ascending `X-APPLE-SORT-ORDER`), `due`, `start`,
`priority` (high first), and `summary` (case-insensitive). Missing manual and
date values sort last. The task identity is always the final deterministic
tie-breaker. When `[sorting]` is omitted, the default remains `completed`,
`priority`, then `summary`. Manual order is read-only for now: rearranging
Markdown lines does not write `X-APPLE-SORT-ORDER`.

`after_apply` is an optional argument array executed directly after source
files change. A failure is reported through LSP but does not roll back the
applied transaction. It is the only hook; an unknown key under `[hooks]`, such
as the removed `before_session` and `after_session`, is a configuration error.

## Commands

| Command | Effect |
|---|---|
| `todomd` | Edit every discovered list. |
| `todomd edit [LISTS]...` | Edit the named lists, or every list. |
| `todomd show [LISTS]...` | Print tasks as JSON. |
| `todomd lsp` | Run the language server for editor integration. |

| Option | Effect |
|---|---|
| `--config <PATH>` | Use a specific configuration file. Accepted anywhere. |
| `--completed` | Include completed and cancelled tasks. |
| `--no-hooks` | `edit` only. Skip `after_apply` for this run. |

Naming lists selects them and fixes their order; otherwise lists are ordered by
display name. The top level takes no list names, so a list called `show` remains
reachable as `todomd edit show`.

## Editing

`todomd` writes a private session document and opens it with `$VISUAL`, falling
back to `$EDITOR`:

```markdown
# Postgrad

- [ ] -2026-09-12 +"2026-09-07 09:00" !!! @Postgrad Paper <!--t1-->
  - [ ] -2026-09-11 ! @"Quick Win" Read related work <!--t3-->

# Personal

- [ ] Buy milk, bread <!--t2-->
```

When a selected vdir has a `color` metadata file containing `#RRGGBB`, todomd
exposes that color for its list heading through LSP. Supporting editors such as
Helix 25.07 and newer show an inline color swatch beside the heading.

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

The `<!--t1-->` markers are session-local identities, not VTODO UIDs, and track
a task across renames and moves. Removing one is treated as intentional: the old
task is deleted and a new one created on the next save.

Only a trailing comment whose body is a session identity, meaning `t` followed by
digits, is read as a marker. Any other trailing HTML comment, such as
`- [ ] Ship it <!--later-->`, is part of the summary, as is an identity-shaped
one that is not at the end of the line. A summary that really does end with
`<!--t1-->` is quoted, like any other summary the syntax would otherwise claim.

Indentation edits the child's `RELATED-TO` parent, written as
`RELATED-TO;RELTYPE=PARENT` so clients that do not infer the default
relationship type, such as todoman, still see the hierarchy. A bare
`RELATED-TO` is read as a parent but rewritten only when that task is
reparented. Removing a parent line deletes only that VTODO. Retained children
must be unindented or nested under another parent. Moving a nested block moves
every line in it. Empty and dangling source relationships render as roots and
remain untouched; cyclic relationships abort the read because they cannot form a
tree.

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

Each sibling set follows its configured sort keys. By default it renders
unfinished first, then by priority, then alphabetically. Parents precede their
recursively sorted descendants. Ordering among siblings is presentational, so
rearranging their lines changes nothing. The `manual` key honors existing
`X-APPLE-SORT-ORDER` values but does not make rearrangement persistent yet.

A summary is quoted only when its start would otherwise be read as syntax, so
ordinary text is never quoted:

| Summary | Rendered |
|---|---|
| `Write paper draft` | `- [ ] Write paper draft` |
| `He said "hi" to me` | `- [ ] He said "hi" to me` |
| `!urgent thing` | `- [ ] "!urgent thing"` |
| `@home is literal` | `- [ ] "@home is literal"` |
| `"quoted" start` | `- [ ] """quoted"" start"` |
| `Ship it <!--t1-->` | `- [ ] "Ship it <!--t1-->"` |

Quote a summary yourself if you start it with `!`, `+`, `-`, `@`, or `"`, if it
ends with an identity-shaped comment such as `<!--t1-->`, or if it needs leading
or trailing spaces. Inside quotes, write `""` for a literal `"`.

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

## Live editing

`todomd edit` keeps the editor open and treats each valid save as approval to
apply its semantic transaction. The editor must start `todomd lsp` as a Markdown
language server; editing fails rather than silently doing nothing if the server
does not attach within ten seconds.

For Helix, add the server alongside any existing Markdown server in
`languages.toml`:

```toml
[language-server.todomd]
command = "todomd"
args = ["lsp"]

[[language]]
name = "markdown"
language-servers = ["marksman", "todomd"]
```

Helix shows its LSP progress spinner by default. To also print the accompanying
text below the statusline, add this to `config.toml`:

```toml
[editor.lsp]
display-progress-messages = true
```

todomd reports when it is updating Markdown from source-side ICS changes and
while an `after_apply` hook is running. An outgoing transaction reports
`changes applied` before hook progress begins, so a slow synchronization hook
does not delay confirmation that the ICS write succeeded. Clients without
work-done progress support retain informational and error messages.

The server ignores ordinary Markdown and attaches only to private todomd live
sessions. It validates the current buffer while typing and reports errors on
their lines. Saving valid Markdown applies it without confirmation, rerenders
session identities, and sends the canonical document back as a versioned LSP
workspace edit. Tasks completed in the current active-scope session stay visible
and can be reopened without restarting with `--completed`. This may leave the
buffer marked modified, but does not require `:reload`.

Selected list directories are watched for source changes. An ICS-only change is
sent into the open buffer through the same mechanism. If both the buffer and
sources changed from the accepted baseline, neither is modified and the editor
shows a conflict diagnostic. `after_apply` runs after every successful outgoing
transaction. Closing the editor retains the session and numbered transaction
artifacts.

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

Tasks are ordered by list and tree using the configured sibling sort keys.
`completed` may be `true` in the
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
| `accepted.md` | Last canonical live document, for recovery and reattachment. |
| `live.json` | Resolved live-session configuration and selected lists. |
| `unaccepted.md` | Buffer contents present when a live session closed with unapplied edits. |
| `transactions/0001/` | Staged files, per-file backups, and `plan.json`. |

Sessions are retained when the editor closes. Invalid or unaccepted buffer
contents are additionally preserved as `unaccepted.md`.

## Exit codes

`0` after a normally closed, attached editor session. Setup, attachment, editor,
and termination failures exit non-zero; transaction errors are reported through
LSP while the session remains open.

## Limitations

- Active tasks only, unless `--completed` is given.
- Tasks without a summary are never rendered, only reported.
- Summaries, hierarchy, start and due dates, priority, completion, and list
  membership are the only editable fields.
- `show` reports tasks, not lists, so an empty list does not appear.
- One primary VTODO per `.ics` file.
- Live editing requires an LSP client with versioned workspace-edit support.
- No CalDAV and no automatic crash recovery.
- Concurrency is optimistic: source changes are reconciled or reported as
  conflicts, but the vdir is not locked.
