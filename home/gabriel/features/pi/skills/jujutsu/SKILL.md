---
name: jujutsu
description: "REQUIRED for every version-control task in a Jujutsu workspace (`jj root` succeeds): status, diff, log, commit/describe, bookmark, push/fetch, PR, rebase, split, squash, conflict, operation recovery, or workspace work. Use jj exclusively; this skill provides a non-interactive inspect-act-verify protocol and prevents agents from mutating the wrong working-copy commit."
---

# Jujutsu Agent Protocol

Use this protocol whenever `jj root` succeeds from the current directory. Do not translate a Git workflow command-for-command; reason from jj's working-copy commit and graph.

## Non-negotiable rules

- Use `jj` exclusively for VCS operations. Do not run raw `git` commands in a jj repo, including a colocated `.jj/` + `.git/` repo.
- Never run `jj git push` unless the user explicitly said **push**. Preparing, committing, shipping, or opening a PR does not imply permission to push.
- Never use interactive/editor forms (`-i`, `--interactive`, bare commands that open an editor, `jj resolve`, or `jj diffedit`). Supply messages with `-m`.
- Before editing or mutating history, inspect the full status, graph position, and relevant diff. Do not assume `@` is where a previous agent left it.
- Prefer stable change IDs (letters such as `nmwwolux`) over changing hexadecimal commit IDs.
- After every history mutation, verify with `jj status`, `jj log`, and the relevant `jj diff`/`jj show`.
- If syntax or behavior is uncertain, use `jj help` instead of guessing; the integrated help matches the active jj version.
- If a mutation has an unexpected result, stop and inspect `jj op log`. Prefer an explicit `jj op revert <op-id>` or `jj op restore <op-id>` over the implicit target selected by `jj undo`.

## Built-in documentation

Prefer jj's integrated, version-correct help over remembered syntax or web examples:

```bash
jj help                         # command list, global options, short descriptions
jj help <command>               # usage, arguments, options, behavior, and examples
jj help <command> <subcommand>  # nested help, e.g. `jj help git push`
jj help -k <keyword>            # conceptual and language reference
```

Use command help before running an unfamiliar command or when flags may have changed. `jj <command> --help` is equivalent, but `jj help ...` composes naturally for nested subcommands.

Keyword topics:

| Keyword | Covers |
|---|---|
| `bookmarks` | Bookmark semantics, remotes, tracking, and Git branch mapping |
| `config` | Configuration files, scopes, precedence, values, and settings |
| `filesets` | Selecting files with patterns, operators, functions, and quoting |
| `glossary` | Canonical jj terminology |
| `revsets` | Selecting revisions with symbols, operators, functions, and patterns |
| `templates` | Customizing command output with `-T`/`--template` |

For example, run `jj help -k revsets`. Run `jj help --help` to list all supported keyword values.

## Mental model

- The working copy is a mutable commit named `@`. jj snapshots file edits at the start of most jj commands; there is no staging area.
- `jj new` creates a new empty child commit. After completing and reviewing a described change, use it as a boundary so the completed content is in `@-` and future edits land in a clean `@`.
- `jj commit -m ...` is equivalent to describing the current commit and then running `jj new`; completed content is then in `@-`.
- Bookmarks are named pointers, not current branches. They follow rewrites of the change they point to but do not advance to newly created child changes.
- Conflicts are stored in commits. A rebase may finish successfully while leaving conflicted commits.
- Rewrites preserve the change ID and replace the commit ID. The operation log makes repo-level recovery possible.

## Required preflight

Run from the repository, before making edits:

```bash
jj root
jj log -r '@ | @-' --no-graph
jj diff
jj status
```

Classify `@` before touching files:

| State of `@` | Action |
|---|---|
| Empty and undescribed | Safe starting point; describe it for this task. |
| Empty but described | It may reserve another task. Continue only if its description matches; otherwise `jj new`. |
| Non-empty | Inspect the full diff and description. Continue only when it belongs to this task; otherwise preserve it and `jj new`. |
| Conflicted | Resolve or deliberately work above it; never silently treat it as clean. |

When existing work is ambiguous or unrelated, preserve it in place and start a fresh `@` with `jj new`. Never squash, abandon, restore, or redescribe existing work merely to obtain a clean state.

## Blessed coding workflow: describe first, close with new

Use one workflow consistently:

```bash
# After preflight confirms @ is safe for this task
jj describe -m "<description>"

# Edit files and run project checks

# Review the completed change while it is still @
jj diff
jj log -r '@ | @-' --no-graph
jj status

# Only after checks and review pass, close it by moving to a clean child
jj new
jj log -r '@ | @-' --no-graph
jj status
jj show @-
```

- Keep one logical change in `@`.
- Review the complete diff before closing the change; do not use `jj new` to hide unfinished or unchecked work.
- End the task with the completed, described change at `@-` and a new empty, undescribed `@` for future edits.
- If the user explicitly requests `jj commit`, use `jj commit -m ...` instead of the separate `jj describe` and final `jj new`. Do not move bookmarks without inspecting them.

## Stack cleanup recommendations

Before the final response, inspect the nearby mutable history. If adjacent commits would be clearer as one logical review unit, suggest a cleanup plan; do not perform it without approval.

Good squash candidates include fixups, tests or documentation inseparable from an implementation, and successive commits editing the same behavior. Keep commits separate when they are independently reviewable or revertible, even if they are small.

A recommendation must include:

- The shortened, unambiguous source and destination change IDs (as rendered by `change_id.short()`) with their current descriptions.
- Why they belong together.
- The proposed combined description.
- An explicit statement that no rewrite has happened yet.

Treat direct approval such as “do it” as authorization for exactly the proposed cleanup. Then re-run preflight, inspect every affected commit's full diff and graph relationship, confirm they are mutable, and apply the plan with explicit change IDs and non-interactive messages. For example:

```bash
jj squash --from '<source1> | <source2>' --into <destination> \
  -m "<combined description>"
# For description-only cleanup:
jj describe -r <change-id> -m "<new description>"
```

Afterward, verify status, graph, destination diff, descriptions, bookmarks, and conflicts. If the result differs from the approved plan, stop and inspect `jj op log`.

## Safe mutation pattern

For any rewrite or destructive-looking operation:

1. Inspect `jj status`, `jj log`, and `jj show <change-id>`/`jj diff`.
2. State exactly which change(s) will move and where.
3. Use explicit revisions and non-interactive flags.
4. Verify graph, status, diff, bookmarks, and conflicts afterward.

Examples:

```bash
jj split path/to/file -m "<first description>"
jj squash --from <source> --into <destination> \
  -m "<resulting description>"
jj rebase -s <source> -d <destination>
jj restore --from <revision> path/to/file
jj abandon <change-id>
```

Do not use a bare `jj squash` when both descriptions may be non-empty; it can request message editing or produce the wrong description. Do not use a destination bookmark as shorthand until `jj log` proves which commit it resolves to.

## Push gate

Only after the user explicitly says **push**:

```bash
jj status
jj bookmark list --all
jj log -r '<bookmark> | present(<bookmark>@origin)' --no-graph
jj show <bookmark>
jj git push -b <bookmark>
```

Push one named bookmark; never use bare `jj git push` or `--all`. Never move or push `main`/the default branch unless the user explicitly names that exact target.

## Conflicts and recovery

- Resolve conflicts by editing markers directly, then verify with `jj status` and `jj log -r 'conflicts()'`.
- For an unexpected mutation, inspect `jj op log` and the relevant historical state with `jj --at-op=<op-id> log` before recovering.
- Use `jj op revert <op-id>` to invert one specific operation while preserving later operations. Revert additional explicitly selected operations separately if needed.
- Use `jj op restore <op-id>` to return the repository to that operation's state, intentionally discarding the effects of all later operations.
- Avoid `jj undo`: its implicit “last operation” target is less precise than either explicit recovery command.
- For a stale workspace, run `jj workspace update-stale`, then inspect for divergence.
- Never use raw Git as a recovery fallback.
