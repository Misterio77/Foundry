---
description: Commit the current VCS change
argument-hint: "[instructions]"
---
Commit the current VCS change. Extra instructions from me, if any: $ARGUMENTS

Workflow:
1. Identify the harness/model first with `ps -fp $PPID` if you have not already done so in this session.
2. Inspect repository state before mutating anything:
   - If `jj root` succeeds, use Jujutsu only: `jj st`, `jj log`, and `jj diff`.
   - Otherwise, if `git rev-parse --show-toplevel` succeeds, use Git: `git status --short`, `git diff --cached`, and `git diff`.
3. Plan a concise conventional-commit style message matching the repo's conventions when available.
4. Review whether the change should be split before committing it.
   - If the message would contain "X and Y", with X and Y being independently commitable changes, it's a splitting candidate.
   - Keep clearly unrelated/concurrent changes out.
5. Apply it non-interactively:
   - Jujutsu: finish the change with `jj commit -m ...`. Prefer `jj commit` (equivalent to `jj describe ... && jj new`) and do not stop after `jj describe`; it should leave a new empty working-copy commit.
   - Git: commit staged changes with `git commit -m ...`; do not stage unstaged files unless I explicitly asked you to.
6. Verify with status/log afterwards. For Jujutsu, confirm that `@` is empty and its parent is the newly committed change.
