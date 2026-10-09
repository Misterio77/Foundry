---
description: Capture todos in todomd and other context in its workspace
argument-hint: "<topic/details>"
---
Capture the following in the context it belongs to: $ARGUMENTS

Workflow:
1. Route durable personal todos to `todomd` using the `gabs-tools` skill and its non-interactive `.ics` writing and sync workflow. Do not create a Markdown todo list instead. For mixed requests, keep the task in `todomd` and supporting context in its workspace.
2. Put other context in the relevant project or workspace, following its `AGENTS.md` and existing layout. Keep agent-authored handoffs in that workspace's `.agents/` directory; do not edit human-written notes unless explicitly requested. If the destination is unclear, ask rather than creating a catch-all notes directory.
3. Before changing repository files, check version control from the destination repository. If `jj root` succeeds, load the `jujutsu` skill and follow its full preflight and workflow. Otherwise, check for Git and inspect status and the relevant diff. Preserve unrelated work.
4. Create a separate, clearly named Markdown file for workspace context; do not append to an unrelated existing note unless I explicitly ask for that. Follow the workspace's naming convention.
5. Do not assume drafts, code changes, or other context exist. If I refer to a diff, command, URL, or file, inspect/read it first and summarize what it actually says.
6. Keep the context factual and useful for future me: relevant paths/commands, open questions, and project-specific next steps. Durable todos remain in `todomd`, not a duplicate task backlog here.
7. Verify the result using the destination's workflow. Repository commits must follow local conventions and include the required `Assisted-by` trailer. Todo changes must be synced as instructed by `gabs-tools`.
8. Tell me the resulting workspace path or todo list/item, and any commit description.
