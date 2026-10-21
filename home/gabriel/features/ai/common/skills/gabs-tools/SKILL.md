---
name: gabs-tools
description: Check Gabs's overall pending work and deadlines with todomd, and manage durable todos, appointments (khal), contacts (khard), and email (~/Mail). Use for questions like "what's pending on my end?" even when a project workspace is in context.
---

## Syncing vdir-backed data

After writing vdir data directly — `.ics` edits, `khal`, `khard`, hand-edited
files — start vdirsyncer so the change propagates:

```bash
systemctl --user start vdirsyncer
```

`todomd session apply` runs the same sync itself through the `after_apply` hook;
don't start vdirsyncer separately after it.

## Todos (todomd + `.ics`)

Todos live as `.ics` files in a vdir at `~/Calendars/personal/`. `todomd`
renders them as Markdown in Gabs's editor; the `.ics` files are authoritative.
`todo` is a fish abbreviation for `todomd`. Todoman is no longer installed.

**Source of truth for Gabs's overall todos:** when asked what's pending, what to do
next, or whether anything remains on their end, run `todomd show` first, without
waiting for an explicit instruction to use it. Use the relevant list (e.g.
`Postgrad`) to narrow the answer when the question has a clear scope. Project
repos, `AGENTS.md`, and `.agents/STATUS.md` hold more granular plans, context,
and dependencies; consult them to interpret a todo or answer project-specific
questions, but don't substitute their next-action lists for the overall todo
list. Distinguish tasks awaiting Gabs from external responses and from
project-internal work not tracked in todomd. Don't assume an unlisted task is
complete; say which source you checked.

### Reading

`todomd show` prints tasks as JSON. It is read-only: no editor, no hooks, no
terminal needed.

```bash
todomd show                       # active tasks in every list
todomd show Postgrad Casa         # chosen lists
todomd show --completed Postgrad  # include completed and cancelled
todomd show --view agenda         # a named view from the config
todomd show --sort-by due,priority --group-by due
```

Each entry has `list`, `uid`, `summary`, `completed`, `priority`,
`categories`, `start`, `due`, `parent_uid`, and `file`:

```json
{
  "list": "Casa",
  "uid": "542812992406319126",
  "summary": "Arrumar fechadura escritório",
  "completed": false,
  "priority": "high",
  "categories": ["Quick Win"],
  "start": null,
  "due": "2026-10-24",
  "parent_uid": null,
  "file": "/home/gabriel/Calendars/personal/7eebf97d-.../542812992406319126.ics"
}
```

Use `file` to reach an item. Filenames are chosen by whatever created the task,
so a UID is not a path: don't construct one, and don't grep for the summary.
`list` is already the display name, so there is no need to map UUID directories
through their `displayname` files.

`SUMMARY` is optional in iCalendar. A task without one cannot be rendered, so
`todomd` skips it and reports the path on stderr.

### Do not run `todomd edit`

`todomd edit`, and bare `todomd`, opens `$VISUAL` and asks `[y/N]` on an
interactive terminal. It also stops vdirsyncer for the duration. That is Gabs's
path, not an agent's.

### Writing: editor-independent sessions

`todomd session` is the agent path. It renders the lists into a `tasks.md`,
applies edits transactionally, and runs the `after_apply` hook for you:

```bash
session=$(todomd session create Postgrad)   # prints the session dir; no lists = every list
# edit "$session/tasks.md"
todomd session apply "$session"             # e.g. "changes applied (1 created, 2 updated)"
todomd session close "$session"             # refuses if tasks.md != accepted.md; --force discards
```

Scope `create` to the lists you actually touch, since loading every list makes
`tasks.md` large. `apply` owns the mechanical parts — `SEQUENCE`, `DTSTAMP`,
`CREATED`, `LAST-MODIFIED`, `COMPLETED`, `PERCENT-COMPLETE`, new UUIDs, and the
sync — so don't hand-write any of them. It keeps the session open, so edit and
apply again as needed. Errors and conflicts preserve the session: read the
message instead of retrying blindly.

`tasks.md` syntax (full spec in `projects/todomd/README.md` in the Foundry repo):

- `- [ ]` / `- [x]` are the only completion switch; `- [x]` completes.
- Leading markers, any order: `@List`, `-YYYY-MM-DD` due, `+"YYYY-MM-DD HH:MM"`
  start, `!`/`!!`/`!!!` priority, `[Cat, "Quick Win"]` full category set.
- Two-space indent makes a child (`RELATED-TO;RELTYPE=PARENT`); unindent detaches.
- Adding a line without `<!--tN-->` creates a VTODO; deleting a line deletes one.
- `<!--tN-->` is session-local identity. Never invent one, copy it between
  sessions, or edit it: a changed or removed marker means delete-and-recreate.

### Writing: direct `.ics` edits

For surgical changes the session view doesn't cover — bulk repair, fields todomd
doesn't render, `.ics` files broken enough that todomd rejects them — edit the
`.ics` at `file` and then run vdirsyncer. Increment `SEQUENCE` on every change.

| Field | Purpose |
|---|---|
| `SUMMARY:` | Todo title |
| `DESCRIPTION:` | Body text |
| `PRIORITY:` | 1=high/`!!!`, 5=medium/`!!`, 9=low/`!` (ical default: 1 highest) |
| `CATEGORIES:` | Comma-separated tags (delete line to remove all categories) |
| `DUE:` | Due date (`YYYYMMDDTHHMMSSZ`, or `DUE;VALUE=DATE:YYYYMMDD`) |
| `STATUS:` | `NEEDS-ACTION`, `IN-PROCESS`, `COMPLETED`, `CANCELLED` |
| `RELATED-TO;RELTYPE=PARENT:` | Parent task's UID, set on the child |
| `SEQUENCE:` | Bump on each edit |

**Completing:** set `STATUS:COMPLETED`, `COMPLETED:<timestamp>`, and
`PERCENT-COMPLETE:100`. Reopening means `STATUS:NEEDS-ACTION` with `COMPLETED`
and `PERCENT-COMPLETE` removed.

**Creating:** write a new `<uid>.ics` in the list's directory. Minimum viable
VTODO:

```ics
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//agent//EN
BEGIN:VTODO
UID:<fresh uuid>
DTSTAMP:20260906T010239Z
CREATED:20260906T010239Z
LAST-MODIFIED:20260906T010239Z
SEQUENCE:0
STATUS:NEEDS-ACTION
SUMMARY:Task text
END:VTODO
END:VCALENDAR
```

**Subtasks:** create the parent first, then put
`RELATED-TO;RELTYPE=PARENT:<parent-uid>` in each child. Use this for shopping
batches: one parent like `mercado` in `Casa`, one child per item.

**Moving between lists:** move the file into the target list's directory.

```bash
mv ~/Calendars/personal/<from-dir>/<uid>.ics ~/Calendars/personal/<to-dir>/
```

### Conventions

Gabs uses categories as tags.

Priority markers: `!!!` (high), `!!` (medium), `!` (low), `Quick Win` (category).
Status markers: `Blocked` (category) — means an **external** dependency prevents progress (e.g. out of supplies, waiting on someone else). NOT "I haven't gotten to it" or "it's my turn." If Gabs could do it right now but hasn't, that's not blocked — that's just pending.

## Appointments (khal)

Calendar stored as vdir `.ics` files under `~/Calendars/personal/Personal/`. Use `khal`.

```bash
khal list today 2d             # today + next 2 days
khal list 12/06/2026 15/06/2026  # specific date range
khal at                         # what's happening right now
khal search "keyword"           # search events

# Create non-interactively (START [END|DELTA] SUMMARY :: DESCRIPTION):
khal new 12/06/2026 18:00 19:00 "Dinner with Ana" -l "Centro" -g food
khal new 20/06/2026 "Viagem" -r weekly -u 20/07/2026 -m 15m
```

`khal new` without arguments, and `khal edit`, are interactive and want a TTY —
avoid both in agent runs. `khal new` also takes `--json TEXT` to print the
created event as JSON. Dates use the khal locale format (`%d/%m/%Y`, not ISO):
`12/06/2026`, and times are `HH:MM`.

**Deleting an event non-interactively:** khal has no `delete` subcommand. Instead, find the `.ics` file and remove it:

```bash
grep -rl "Event Title" ~/Calendars/personal/Personal/
rm /path/to/uid.ics
```

**Deleting a recurring event:** same approach — find the `.ics` containing the `RRULE` and delete it. All instances will vanish.

The underlying sync is done by vdirsyncer. (DAVx5 handles sync on Android.) The vdir is at `~/Calendars/personal/`.

**Cache bust:** khal caches events in `~/.cache/khal/khal.db` and won't pick up manual `.ics` edits. Delete the cache after editing `.ics` files directly:

```bash
rm ~/.cache/khal/khal.db
```

## Workspace context

Durable personal todos belong in `todomd` and its authoritative `.ics` files.
Do not create a parallel todo list in Markdown. Project plans, research notes,
drafts, and other context belong in the workspace they concern, following its
`AGENTS.md` and existing layout. Agent-authored handoffs belong in that workspace's
`.agents/` directory. If the relevant workspace is unclear, ask rather than
creating a catch-all notes directory.

## Contacts (khard)

khard is a CardDAV address book client. Contacts are synced via vdirsyncer.

**To look up a contact, always use `khard show <name>` first.** It handles fuzzy matching and gives you everything (email, phone, notes, UID) in one shot. Only fall back to grep on `~/Contacts/Main/` for bulk operations or when khard misbehaves.

```bash
khard show <name>             # full contact details (phone, address, notes, etc.) — use this first
khard emails                  # list all contacts that have email addresses
khard list                    # list all contacts
```

### Editing contacts

`khard edit <name>` opens the contact in `$EDITOR`, but requires a TTY and will not work from a non-interactive agent shell. The fallback is to edit the vCard file directly:

```bash
# Find the vCard by UID (shown in khard show output under Miscellaneous > UID)
file=~/Contacts/Main/<UID>.vcf
```

Or grep for the name:

```bash
grep -rl "<name>" ~/Contacts/Main/
```

Then edit the `.vcf` file directly. `NOTE:` is the notes field.

## Email (~/Mail)

Mail lives in `~/Mail/` as a Maildir. Each account gets a subdirectory:

| Path | Account |
|---|---|
| `~/Mail/personal/` | hi@m7.rs (forwards from gabriel@gsfontes.com) |
| `~/Mail/usp/` | g.fontes@usp.br |

### Maildir layout

Standard Maildir: `Inbox/{cur,new,tmp}` plus `Archive/`, `Drafts/`, `Junk/`, `Sent/`, `Trash/`.

**Syncing:** mbsync syncs automatically via a systemd timer. To force an immediate sync:
```bash
systemctl --user start mbsync
```

All mail in `new/` has already been synced by mbsync — `new/` and `cur/` both contain read mail. Email files are named like:

```
<unix_ts>.<seq>_<host>,U=<uid>:2,<flags>
```

**Flags** (appended after `:2,`):
| Flag | Meaning |
|---|---|
| `S` | Seen (read) |
| `F` | Flagged (important/starred) |
| `R` | Replied |

Flags can combine, e.g. `,FRS` = Flagged + Replied + Seen.

**Moving files between mailboxes:** Always strip the `,U=<uid>` portion from the filename when moving a file to a different Maildir folder (e.g. Inbox to Archive). Otherwise the UID can clash with an existing file in the destination, causing mbsync to error out with "duplicate UID". mbsync will assign a fresh UID on the next sync.

```bash
# Strip UID before moving:
f="${src##*/}" && mv "$src" "$dest/${f//,U=[0-9]*:/:}"
```

### Reading email — workflow

1. **Get an overview first.** Use `rg '^(Subject|From|Date):'` across `Inbox/cur/` to survey what's there before reading bodies.

2. **Check size before reading.** Some emails contain huge base64-encoded attachments (especially .docx, PDFs, images). List with `ls -lS` first, then read only a leading slice. With the file tools that means `read` with `limit=160`; from bash, `sed -n '1,160p' <file>`. Emails with attachments often stretch to 500+ lines.

3. **Look for `text/plain` first.** Most emails are `multipart/alternative` with both `text/plain` and `text/html`. The plaintext part is the message without HTML soup. The boundary marker is like `--000000000000...`; skip past the headers to the `Content-Type: text/plain;` block.

4. **Decode properly instead of eyeballing.** Bodies are often `base64` or `Content-Transfer-Encoding: quoted-printable` (`=C3=A7` for `ç`). One decoder handles both, charsets included:

   ```bash
   python3 -c '
   import email, email.policy, pathlib, sys
   m = email.message_from_bytes(pathlib.Path(sys.argv[1]).read_bytes(), policy=email.policy.default)
   print(m.get_body(("plain", "html")).get_content())' ~/Mail/personal/Inbox/cur/<file>
   ```

5. **Flagged emails are worth highlighting.** When summarizing, call out emails with `F` in the flags — Gabs intentionally marks these as important.

6. **Sort order.** Files sort by the Unix timestamp prefix in the filename, so `ls` order is chronological.

### Example: reading all inbox email

```bash
# Step 1: overview
rg --no-heading '^(Subject|From|Date):' ~/Mail/personal/Inbox/cur/ ~/Mail/usp/Inbox/cur/

# Step 2: sizes first, then a leading slice
ls -lS ~/Mail/personal/Inbox/cur/ | head
sed -n '1,160p' ~/Mail/personal/Inbox/cur/<file>

# Step 3: full decoded body when the raw message is base64 or quoted-printable
python3 -c '
import email, email.policy, pathlib, sys
m = email.message_from_bytes(pathlib.Path(sys.argv[1]).read_bytes(), policy=email.policy.default)
print(m.get_body(("plain", "html")).get_content())' ~/Mail/personal/Inbox/cur/<file>
```

### Sending email

Gabs uses a desktop email client. To compose a new message, use:

```bash
handlr open mailto:<address>
```

This opens the client's compose window pre-filled with the recipient. For a blank compose window, omit the address:

```bash
handlr open mailto:
```

### Drafts and Sent

- `~/Mail/personal/Sent/cur/`
- `~/Mail/usp/Sent/cur/`

These use the same Maildir layout. Read them the same way.
