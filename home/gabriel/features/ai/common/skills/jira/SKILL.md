---
name: jira
description: Use go-jira to read Jira tickets, attached change-request forms, and AI feedback; edit form answers and verify linked ticket fields.
---

# Jira

- **go-jira** (`jira`) reads server, login, project, and credential source from `~/.jira.d/config.yml`, with directory-local `.jira.d` overrides.
- Read tickets with `jira view <issue-key>`. Use `jira request '<path-or-url>'` for JSON; `--gjq '<query>'` filters output. Relative paths use the configured endpoint; full URLs also receive configured authentication, so use only trusted Jira/Atlassian endpoints.
- Write with `jira request --method PUT '<path-or-url>' '<json>'`. Python can invoke it via `subprocess.run([...], capture_output=True, text=True, check=True)` and parse stdout with `json.loads`.
- go-jira handles authentication for CLI and API requests.

## Ticket details and AI feedback

`jira view` omits form/custom fields by default. Use `jira request '/rest/api/2/issue/{key}?expand=names'` to map field IDs to labels. AI feedback is in **AI RISK** and its history at `/rest/api/2/issue/{key}/changelog` (paginate). Match fields by their actual labels; feedback may cite incorrect IDs.

## Forms

Use `jira request '/_edge/tenant_info' --gjq cloudId` for `cloudId`. Forms API base:
`https://api.atlassian.com/jira/forms/cloud/{cloudId}/issue/{key}`. Pass full URLs to `jira request`; go-jira handles authentication.

1. GET `/form` to list forms; GET `/form/{id}` for layout, questions, and saved answers.
2. Match `design.questions` by label or `jiraField`; answers are keyed by question ID. Rich text uses Atlassian Document Format (`adf`); choices use option IDs.
3. To edit an open form, preserve all other answers and PUT `/form/{id}` with `{"answers": <complete updated answers>}`. Form edits synchronize linked ticket fields. Obtain user authorization for edits, submission, or reopening.
4. Re-fetch to verify only the intended answer changed; verify the linked ticket field synchronized (allow a short delay).

Form-only answers (e.g. test evidence and rollback duration) may not appear in ticket fields. Render ADF as Markdown and respect conditional sections.
