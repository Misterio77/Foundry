---
name: jujutsu
description: "REQUIRED for every version-control task in a Jujutsu repository (`.jj/` present): status, diff, log, commit/describe, bookmark, push/fetch, PR, rebase, split, squash, conflict, undo, recovery, or workspace work. Use jj exclusively; this skill provides a non-interactive inspect-act-verify protocol and prevents agents from mutating the wrong working-copy commit."
---

# Jujutsu Agent Protocol

Use this protocol whenever `.jj/` is present. Do not translate a Git workflow command-for-command; reason from jj's working-copy commit and graph.

## Non-negotiable rules

- Use `jj` exclusively for VCS operations. Do not run raw `git` commands in a jj repo, including a colocated `.jj/` + `.git/` repo.
- Never run `jj git push` unless the user explicitly said **push**. Preparing, committing, shipping, or opening a PR does not imply permission to push.
- Never use interactive/editor forms (`-i`, `--interactive`, bare commands that open an editor, `jj resolve`, or `jj diffedit`). Supply messages with `-m`.
- Before editing or mutating history, inspect the full status, graph position, and relevant diff. Do not assume `@` is where a previous agent left it.
- Prefer stable change IDs (letters such as `nmwwolux`) over changing hexadecimal commit IDs.
- After every history mutation, verify with `jj st`, `jj log`, and the relevant `jj diff`/`jj show`.
- If syntax or behavior is uncertain, run `jj --version` and `jj help <command>` instead of guessing. jj's CLI changes quickly.
- If a mutation has an unexpected result, stop. Inspect `jj op log`; use `jj undo` only after identifying the operation to reverse.

## Mental model

- The working copy is a mutable commit named `@`. jj snapshots file edits at the start of most jj commands; there is no staging area.
- `jj new` creates a new empty child commit. It does **not** finish or commit the current work.
- `jj commit -m ...` describes the current commit and creates a new empty `@`; completed content is then in `@-`.
- Bookmarks are named pointers, not current branches. They follow rewrites of the change they point to but do not advance to newly created child changes.
- Conflicts are stored in commits. A rebase may finish successfully while leaving conflicted commits.
- Rewrites preserve the change ID and replace the commit ID. The operation log makes repo-level recovery possible.

## Required preflight

Run from the repository, before making edits:

```bash
jj root
jj st
jj log -r '@ | @-' --no-graph
jj diff
```

Classify `@` before touching files:

| State of `@` | Action |
|---|---|
| Empty and undescribed | Safe starting point; describe it for this task. |
| Empty but described | It may reserve another task. Continue only if its description matches; otherwise `jj new`. |
| Non-empty | Inspect the full diff and description. Continue only when it belongs to this task; otherwise preserve it and `jj new`. |
| Conflicted | Resolve or deliberately work above it; never silently treat it as clean. |

When existing work is ambiguous or unrelated, preserve it in place and start a fresh `@` with `jj new`. Never squash, abandon, restore, or redescribe existing work merely to obtain a clean state.

## Blessed coding workflow: describe first

Use one workflow consistently:

```bash
# After preflight confirms @ is safe for this task
jj describe -m "<description>"

# Edit files and run project checks

jj st
jj diff
jj log -r '@ | @-' --no-graph
```

- Keep one logical change in `@`.
- Review the complete diff before calling the task done or writing a final description.
- Leave the completed, described change at `@`. Do **not** run `jj new` at the end; start the next task with it after inspecting state.
- If the user explicitly requests `jj commit`, use `jj commit -m ...`, then remember that content moved to `@-`. Do not move bookmarks without inspecting them.

## Safe mutation pattern

For any rewrite or destructive-looking operation:

1. Inspect `jj st`, `jj log`, and `jj show <change-id>`/`jj diff`.
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
jj st
jj bookmark list --all
jj log -r '<bookmark> | present(<bookmark>@origin)' --no-graph
jj show <bookmark>
jj git push -b <bookmark>
```

Push one named bookmark; never use bare `jj git push` or `--all`. Never move or push `main`/the default branch unless the user explicitly names that exact target.

## Conflicts and recovery

- Resolve conflicts by editing markers directly, then verify with `jj st` and `jj log -r 'conflicts()'`.
- For an unexpected mutation, inspect `jj op log` before choosing `jj undo` or `jj op restore <op-id>`.
- For a stale workspace, run `jj workspace update-stale`, then inspect for divergence.
- Never use raw Git as a recovery fallback.
