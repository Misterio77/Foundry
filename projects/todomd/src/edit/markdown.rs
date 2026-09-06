use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::model::{
    EditedTask, EditedTaskList, EditedTaskState, Priority, TaskId, TaskReference, TaskState,
};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct IdentityManifest {
    ids: BTreeMap<TaskId, String>,
    next_id: usize,
}

impl IdentityManifest {
    pub fn session_id(&self, task_id: &TaskId) -> Option<&str> {
        self.ids.get(task_id).map(String::as_str)
    }

    pub fn resolve_session_id(&self, session_id: &str) -> Result<&TaskId> {
        let mut matches = self
            .ids
            .iter()
            .filter(|(_, candidate)| candidate.as_str() == session_id)
            .map(|(task_id, _)| task_id);
        let task_id = matches
            .next()
            .with_context(|| format!("unknown todomd identity {session_id:?}"))?;
        if matches.next().is_some() {
            bail!("duplicate todomd identity {session_id:?} in manifest");
        }
        Ok(task_id)
    }

    fn get_or_insert(&mut self, task_id: &TaskId) -> &str {
        self.ids.entry(task_id.clone()).or_insert_with(|| {
            self.next_id += 1;
            format!("t{}", self.next_id)
        })
    }
}

pub fn render(state: &TaskState, manifest: &mut IdentityManifest) -> Result<String> {
    let mut output = String::new();

    for (list_index, list) in state.lists.iter().enumerate() {
        validate_heading(&list.name)?;
        if list_index > 0 {
            output.push('\n');
        }
        output.push_str("# ");
        output.push_str(&list.name);
        output.push_str("\n\n");

        let mut depths = BTreeMap::new();
        for task in &list.tasks {
            validate_summary(&task.summary)?;
            let depth = match &task.parent {
                Some(parent) => {
                    depths.get(parent).copied().with_context(|| {
                        format!(
                            "task {:?} appears before its parent {:?}",
                            task.id.as_str(),
                            parent.as_str()
                        )
                    })? + 1
                }
                None => 0,
            };
            let checked = if task.completed { 'x' } else { ' ' };
            let priority = match task.priority.marker() {
                "" => String::new(),
                marker => format!("{marker} "),
            };
            let summary = render_summary(&task.summary);
            let session_id = manifest.get_or_insert(&task.id);
            output.push_str(&"  ".repeat(depth));
            output.push_str(&format!(
                "- [{checked}] {priority}{summary} <!-- todomd:id={session_id} -->\n"
            ));
            depths.insert(task.id.clone(), depth);
        }
    }

    Ok(output)
}

pub fn parse(
    input: &str,
    baseline: &TaskState,
    manifest: &IdentityManifest,
) -> Result<EditedTaskState> {
    let expected_lists = baseline
        .lists
        .iter()
        .map(|list| list.name.as_str())
        .collect::<BTreeSet<_>>();
    let mut parsed_lists: BTreeMap<String, Vec<EditedTask>> = BTreeMap::new();
    let mut current_list: Option<String> = None;
    let mut seen_ids = BTreeSet::new();
    let mut ancestors: Vec<TaskReference> = Vec::new();
    let mut next_draft_id = 1;

    for (index, line) in input.lines().enumerate() {
        let line_number = index + 1;
        if line.trim().is_empty() {
            continue;
        }

        if let Some(name) = line.strip_prefix("# ") {
            if !expected_lists.contains(name) {
                bail!("line {line_number}: unknown list heading {name:?}");
            }
            if parsed_lists.insert(name.to_owned(), Vec::new()).is_some() {
                bail!("line {line_number}: duplicate list heading {name:?}");
            }
            current_list = Some(name.to_owned());
            ancestors.clear();
            continue;
        }

        if line.starts_with('#') {
            bail!("line {line_number}: only level-one selected-list headings are allowed");
        }

        let list_name = current_list
            .as_ref()
            .with_context(|| format!("line {line_number}: task appears before a list heading"))?;
        let (depth, task_line) = split_indentation(line, line_number)?;
        if depth > ancestors.len() {
            bail!("line {line_number}: task nesting jumps more than one level");
        }
        let mut task = parse_task_line(task_line, line_number, manifest)?;
        if let Some(task_id) = &task.id
            && !seen_ids.insert(task_id.clone())
        {
            bail!("line {line_number}: duplicate task identity");
        }
        let task_reference = match &task.id {
            Some(task_id) => TaskReference::Existing(task_id.clone()),
            None => {
                let reference = TaskReference::Draft(next_draft_id);
                next_draft_id += 1;
                reference
            }
        };
        task.parent = depth.checked_sub(1).map(|index| ancestors[index].clone());
        ancestors.truncate(depth);
        ancestors.push(task_reference);
        parsed_lists
            .get_mut(list_name)
            .expect("current list heading was inserted")
            .push(task);
    }

    let missing = expected_lists
        .iter()
        .filter(|name| !parsed_lists.contains_key(**name))
        .copied()
        .collect::<Vec<_>>();
    if !missing.is_empty() {
        bail!("missing list heading(s): {}", missing.join(", "));
    }

    let lists = baseline
        .lists
        .iter()
        .map(|list| EditedTaskList {
            name: list.name.clone(),
            tasks: parsed_lists
                .remove(&list.name)
                .expect("all baseline headings were checked"),
        })
        .collect();

    Ok(EditedTaskState { lists })
}

fn split_indentation(line: &str, line_number: usize) -> Result<(usize, &str)> {
    let spaces = line.bytes().take_while(|byte| *byte == b' ').count();
    if line[..spaces].contains('\t') || line.as_bytes().get(spaces) == Some(&b'\t') {
        bail!("line {line_number}: task indentation must use spaces, not tabs");
    }
    if spaces % 2 != 0 {
        bail!("line {line_number}: task indentation must be a multiple of two spaces");
    }
    Ok((spaces / 2, &line[spaces..]))
}

fn parse_task_line(
    line: &str,
    line_number: usize,
    manifest: &IdentityManifest,
) -> Result<EditedTask> {
    let (completed, remainder) = if let Some(remainder) = line.strip_prefix("- [ ] ") {
        (false, remainder)
    } else if let Some(remainder) = line.strip_prefix("- [x] ") {
        (true, remainder)
    } else {
        bail!("line {line_number}: expected a '- [ ]' or '- [x]' task");
    };

    let (summary, id) = match remainder.rsplit_once(" <!-- todomd:id=") {
        Some((summary, marker)) => {
            let session_id = marker
                .strip_suffix(" -->")
                .with_context(|| format!("line {line_number}: malformed todomd identity marker"))?;
            if session_id.is_empty() || summary.contains("<!-- todomd:id=") {
                bail!("line {line_number}: malformed todomd identity marker");
            }
            let task_id = manifest
                .resolve_session_id(session_id)
                .with_context(|| format!("line {line_number}"))?;
            (summary, Some(task_id.clone()))
        }
        None => {
            if remainder.contains("<!-- todomd:id=") {
                bail!("line {line_number}: malformed todomd identity marker");
            }
            (remainder, None)
        }
    };

    let (priority, field) =
        split_priority(summary).with_context(|| format!("line {line_number}"))?;
    let summary = parse_summary(field).with_context(|| format!("line {line_number}"))?;
    validate_summary(&summary).with_context(|| format!("line {line_number}"))?;

    Ok(EditedTask {
        id,
        summary,
        completed,
        priority,
        parent: None,
    })
}

fn validate_heading(heading: &str) -> Result<()> {
    if heading.is_empty() || heading.contains(['\r', '\n']) {
        bail!("list display name cannot be empty or contain a newline");
    }
    Ok(())
}

/// Quotes a summary only when its start would otherwise be read as syntax, or
/// when edge whitespace would be lost. Interior quotes stay literal.
fn render_summary(summary: &str) -> String {
    if !needs_quoting(summary) {
        return summary.to_owned();
    }
    format!("\"{}\"", summary.replace('"', "\"\""))
}

fn needs_quoting(summary: &str) -> bool {
    summary.starts_with(['!', '"']) || summary.trim() != summary
}

/// Splits an optional priority marker off the front of a task line.
fn split_priority(remainder: &str) -> Result<(Priority, &str)> {
    if !remainder.starts_with('!') {
        return Ok((Priority::None, remainder));
    }

    let marker_len = remainder.chars().take_while(|c| *c == '!').count();
    let (marker, rest) = remainder.split_at(marker_len);
    let priority = Priority::from_marker(marker)
        .with_context(|| format!("unknown priority marker {marker:?}"))?;
    let summary = rest.strip_prefix(' ').context(
        "a summary starting with '!' must be quoted so it is not read as a priority marker",
    )?;

    Ok((priority, summary))
}

/// Reads a summary field, honouring optional quoting.
fn parse_summary(field: &str) -> Result<String> {
    let Some(inner) = field.strip_prefix('"') else {
        if field.starts_with('!') {
            bail!("a summary starting with '!' must be quoted");
        }
        if field.trim() != field {
            bail!("a summary with leading or trailing whitespace must be quoted");
        }
        return Ok(field.to_owned());
    };

    let inner = inner
        .strip_suffix('"')
        .context("a quoted summary must end with '\"'")?;

    let mut summary = String::with_capacity(inner.len());
    let mut characters = inner.chars();
    while let Some(character) = characters.next() {
        if character != '"' {
            summary.push(character);
            continue;
        }
        // Inside quotes, '"' is only legal as the doubled pair '""'.
        if characters.next() != Some('"') {
            bail!("a quoted summary must double any '\"' it contains");
        }
        summary.push('"');
    }

    Ok(summary)
}

fn validate_summary(summary: &str) -> Result<()> {
    if summary.trim().is_empty() {
        bail!("task summary cannot be empty or whitespace-only");
    }
    if summary.contains(['\r', '\n']) {
        bail!("task summary cannot contain a newline in the MVP format");
    }
    if summary.contains("<!-- todomd:id=") {
        bail!("task summary contains a reserved todomd identity marker");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::model::{Task, TaskList};

    use super::*;

    #[test]
    fn rendering_is_stable_with_the_same_manifest() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("groceries@example.test"),
                    summary: "Buy groceries".into(),
                    completed: false,
                    priority: Priority::None,
                    parent: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let first = render(&state, &mut manifest).unwrap();
        let second = render(&state, &mut manifest).unwrap();

        assert_eq!(first, second);
        assert_eq!(manifest.session_id(&state.lists[0].tasks[0].id), Some("t1"));
    }

    #[test]
    fn persisted_manifest_keeps_allocating_unique_ids() {
        let first_id = TaskId::new("first@example.test");
        let second_id = TaskId::new("second@example.test");
        let mut manifest = IdentityManifest::default();
        manifest.get_or_insert(&first_id);
        let serialized = toml::to_string(&manifest).unwrap();
        let mut restored: IdentityManifest = toml::from_str(&serialized).unwrap();

        assert_eq!(restored.get_or_insert(&first_id), "t1");
        assert_eq!(restored.get_or_insert(&second_id), "t2");
    }

    #[test]
    fn parses_moves_edits_completions_and_new_tasks() {
        let baseline = TaskState {
            lists: vec![
                TaskList {
                    name: "Postgrad".into(),
                    tasks: vec![Task {
                        id: TaskId::new("paper@example.test"),
                        summary: "Write paper".into(),
                        completed: false,
                        priority: Priority::None,
                        parent: None,
                    }],
                },
                TaskList {
                    name: "Personal".into(),
                    tasks: Vec::new(),
                },
            ],
        };
        let mut manifest = IdentityManifest::default();
        render(&baseline, &mut manifest).unwrap();
        let input = "# Postgrad\n\n- [ ] Buy coffee\n\n# Personal\n\n- [x] Submit paper <!-- todomd:id=t1 -->\n";

        let parsed = parse(input, &baseline, &manifest).unwrap();

        assert_eq!(parsed.lists[0].tasks[0].id, None);
        assert_eq!(parsed.lists[0].tasks[0].summary, "Buy coffee");
        assert_eq!(
            parsed.lists[1].tasks[0].id.as_ref().map(TaskId::as_str),
            Some("paper@example.test")
        );
        assert_eq!(parsed.lists[1].tasks[0].summary, "Submit paper");
        assert!(parsed.lists[1].tasks[0].completed);
    }

    #[test]
    fn rejects_unknown_identities() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        let error = parse(
            "# Personal\n\n- [ ] Ghost <!-- todomd:id=t404 -->\n",
            &baseline,
            &IdentityManifest::default(),
        )
        .unwrap_err();

        assert!(error.to_string().contains("line 3"));
    }

    #[test]
    fn renders_and_parses_priority_markers() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![
                    Task {
                        id: TaskId::new("high"),
                        summary: "Urgent".into(),
                        completed: false,
                        priority: Priority::High,
                        parent: None,
                    },
                    Task {
                        id: TaskId::new("medium"),
                        summary: "Middling".into(),
                        completed: false,
                        priority: Priority::Medium,
                        parent: None,
                    },
                    Task {
                        id: TaskId::new("low"),
                        summary: "Whenever".into(),
                        completed: false,
                        priority: Priority::Low,
                        parent: None,
                    },
                    Task {
                        id: TaskId::new("none"),
                        summary: "Unset".into(),
                        completed: false,
                        priority: Priority::None,
                        parent: None,
                    },
                ],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();

        assert!(document.contains("- [ ] !!! Urgent <!-- todomd:id=t1 -->"));
        assert!(document.contains("- [ ] !! Middling <!-- todomd:id=t2 -->"));
        assert!(document.contains("- [ ] ! Whenever <!-- todomd:id=t3 -->"));
        assert!(document.contains("- [ ] Unset <!-- todomd:id=t4 -->"));

        let parsed = parse(&document, &state, &manifest).unwrap();
        let priorities = parsed.lists[0]
            .tasks
            .iter()
            .map(|task| task.priority)
            .collect::<Vec<_>>();
        assert_eq!(
            priorities,
            [
                Priority::High,
                Priority::Medium,
                Priority::Low,
                Priority::None
            ]
        );
    }

    #[test]
    fn round_trips_summaries_that_need_quoting() {
        let awkward = [
            "!urgent looking",
            "!!! literal marker",
            "\"quoted\" start",
            "  padded  ",
            "trailing space ",
            "\"",
        ];
        let state = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: awkward
                    .iter()
                    .enumerate()
                    .map(|(index, summary)| Task {
                        id: TaskId::new(format!("task{index}")),
                        summary: (*summary).into(),
                        completed: false,
                        priority: Priority::Medium,
                        parent: None,
                    })
                    .collect(),
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();
        let parsed = parse(&document, &state, &manifest).unwrap();

        let summaries = parsed.lists[0]
            .tasks
            .iter()
            .map(|task| task.summary.as_str())
            .collect::<Vec<_>>();
        assert_eq!(summaries, awkward);
        assert!(
            parsed.lists[0]
                .tasks
                .iter()
                .all(|task| task.priority == Priority::Medium)
        );
        assert!(document.contains(r#"!! "!urgent looking""#), "{document}");
        assert!(document.contains(r#"!! """quoted"" start""#), "{document}");
    }

    #[test]
    fn leaves_summaries_with_interior_quotes_unquoted() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    id: TaskId::new("quotes"),
                    summary: r#"He said "hi" to me"#.into(),
                    completed: false,
                    priority: Priority::None,
                    parent: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();

        assert!(
            document.contains(r#"- [ ] He said "hi" to me <!-- todomd:id=t1 -->"#),
            "{document}"
        );
        let parsed = parse(&document, &state, &manifest).unwrap();
        assert_eq!(parsed.lists[0].tasks[0].summary, r#"He said "hi" to me"#);
    }

    #[test]
    fn rejects_ambiguous_unquoted_summaries() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    id: TaskId::new("task"),
                    summary: "Ordinary".into(),
                    completed: false,
                    priority: Priority::None,
                    parent: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();
        render(&state, &mut manifest).unwrap();

        for line in [
            "- [ ] !!!! Too many <!-- todomd:id=t1 -->",
            "- [ ] !unquoted start <!-- todomd:id=t1 -->",
            "- [ ] \"unterminated <!-- todomd:id=t1 -->",
            "- [ ] \"bad \" quoting\" <!-- todomd:id=t1 -->",
        ] {
            let document = format!("# Postgrad\n\n{line}\n");
            assert!(
                parse(&document, &state, &manifest).is_err(),
                "expected a parse error for {line:?}"
            );
        }
    }

    #[test]
    fn rejects_missing_headings() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };

        assert!(parse("", &baseline, &IdentityManifest::default()).is_err());
    }

    #[test]
    fn rejects_whitespace_only_summaries() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };

        assert!(
            parse(
                "# Personal\n\n- [ ]    \n",
                &baseline,
                &IdentityManifest::default()
            )
            .is_err()
        );
    }

    #[test]
    fn rejects_multiline_summaries() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("bad@example.test"),
                    summary: "first\nsecond".into(),
                    completed: false,
                    priority: Priority::None,
                    parent: None,
                }],
            }],
        };

        assert!(render(&state, &mut IdentityManifest::default()).is_err());
    }

    #[test]
    fn round_trips_arbitrarily_nested_tasks() {
        let root = TaskId::new("root");
        let child = TaskId::new("child");
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![
                    Task {
                        id: root.clone(),
                        summary: "Root".into(),
                        completed: false,
                        priority: Priority::None,
                        parent: None,
                    },
                    Task {
                        id: child.clone(),
                        summary: "Child".into(),
                        completed: false,
                        priority: Priority::None,
                        parent: Some(root.clone()),
                    },
                    Task {
                        id: TaskId::new("grandchild"),
                        summary: "Grandchild".into(),
                        completed: false,
                        priority: Priority::None,
                        parent: Some(child.clone()),
                    },
                ],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();
        assert!(document.contains("  - [ ] Child <!-- todomd:id=t2 -->"));
        assert!(document.contains("    - [ ] Grandchild <!-- todomd:id=t3 -->"));

        let parsed = parse(&document, &state, &manifest).unwrap();
        assert_eq!(
            parsed.lists[0].tasks[1].parent,
            Some(TaskReference::Existing(root))
        );
        assert_eq!(
            parsed.lists[0].tasks[2].parent,
            Some(TaskReference::Existing(child))
        );
    }

    #[test]
    fn nested_new_tasks_reference_parent_drafts() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        let document = "# Personal\n\n- [ ] Parent\n  - [ ] Child\n    - [ ] Grandchild\n";

        let parsed = parse(document, &baseline, &IdentityManifest::default()).unwrap();

        assert_eq!(parsed.lists[0].tasks[0].parent, None);
        assert_eq!(
            parsed.lists[0].tasks[1].parent,
            Some(TaskReference::Draft(1))
        );
        assert_eq!(
            parsed.lists[0].tasks[2].parent,
            Some(TaskReference::Draft(2))
        );
    }

    #[test]
    fn rejects_ambiguous_indentation() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        for document in [
            "# Personal\n\n   - [ ] Odd\n",
            "# Personal\n\n    - [ ] Jump\n",
            "# Personal\n\n\t- [ ] Tab\n",
        ] {
            assert!(
                parse(document, &baseline, &IdentityManifest::default()).is_err(),
                "expected a parse error for {document:?}"
            );
        }
    }
}
