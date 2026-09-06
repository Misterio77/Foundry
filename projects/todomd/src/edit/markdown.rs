use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::model::{EditedTask, EditedTaskList, EditedTaskState, TaskId, TaskState};

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

        for task in &list.tasks {
            validate_summary(&task.summary)?;
            let checked = if task.completed { 'x' } else { ' ' };
            let session_id = manifest.get_or_insert(&task.id);
            output.push_str(&format!(
                "- [{checked}] {} <!-- todomd:id={session_id} -->\n",
                task.summary
            ));
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
            continue;
        }

        if line.starts_with('#') {
            bail!("line {line_number}: only level-one selected-list headings are allowed");
        }

        let list_name = current_list
            .as_ref()
            .with_context(|| format!("line {line_number}: task appears before a list heading"))?;
        let task = parse_task_line(line, line_number, manifest)?;
        if let Some(task_id) = &task.id
            && !seen_ids.insert(task_id.clone())
        {
            bail!("line {line_number}: duplicate task identity");
        }
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

    validate_summary(summary).with_context(|| format!("line {line_number}"))?;
    Ok(EditedTask {
        id,
        summary: summary.to_owned(),
        completed,
    })
}

fn validate_heading(heading: &str) -> Result<()> {
    if heading.is_empty() || heading.contains(['\r', '\n']) {
        bail!("list display name cannot be empty or contain a newline");
    }
    Ok(())
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
                }],
            }],
        };

        assert!(render(&state, &mut IdentityManifest::default()).is_err());
    }
}
