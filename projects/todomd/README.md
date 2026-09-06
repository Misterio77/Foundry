# todomd

`todomd` is a local-first CLI for editing vdir-backed VTODO lists as Markdown.
It turns selected whole lists into a temporary Markdown document, opens the
user's editor, previews the resulting semantic changes, and applies approved
changes back to the source `.ics` files.

The initial version does not speak CalDAV or invoke vdirsyncer directly. It
operates on local vdirs and provides optional lifecycle hooks for users who need
to pause and resume synchronization.

```console
$ todomd Postgrad Personal
```

## Status

Early implementation. `todomd` discovers configured lists, parses their active
VTODO files, creates a private session, and opens its deterministic Markdown
document in `$VISUAL` or `$EDITOR`.

After the editor exits, `todomd` strictly parses the document, rereads the source
vdirs, performs three-way reconciliation, and stages the semantic and filesystem
changes. An explicit `[y/N]` confirmation applies them with source-hash guards,
backups, atomic file replacement, and best-effort rollback. After application,
the accepted Markdown, identity manifest, and baseline are refreshed atomically
per file. Rejected, conflicted, and invalid sessions are retained for inspection;
unchanged and successfully applied sessions are removed by default.

Optional lifecycle hooks can pause external writers for the session and trigger
synchronization after a successful apply. `after_session` still runs when an
edited session fails, conflicts, or receives a handled termination signal.

See [DESIGN.md](DESIGN.md) for the complete design.

## Try it

Create `~/.config/todomd/config.toml`:

```toml
calendar_roots = ["~/Calendars/personal"]

[hooks]
before_session = [
  "systemctl", "--user", "stop",
  "vdirsyncer.timer", "vdirsyncer.service",
]
after_apply = [
  "systemctl", "--user", "start",
  "vdirsyncer.service",
]
after_session = [
  "systemctl", "--user", "start",
  "vdirsyncer.timer",
]
```

Hooks are argument arrays executed directly without a shell. Use `--no-hooks`
to disable them for one invocation, or `--keep` to retain a coherent unchanged
or successfully applied session.

Then run:

```console
$ nix run .#todomd -- Postgrad Personal
```

## Why

VTODO and CalDAV are useful synchronization formats, but existing task CLIs can
make quick, broad edits cumbersome. Markdown offers a low-friction editing
surface without becoming another persistent source of truth.
