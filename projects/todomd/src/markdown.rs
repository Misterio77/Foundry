use std::collections::BTreeMap;

use anyhow::{Result, bail};
use serde::{Deserialize, Serialize};

use crate::model::{TaskId, TaskState};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct IdentityManifest {
    ids: BTreeMap<TaskId, String>,
    next_id: usize,
}

impl IdentityManifest {
    pub fn session_id(&self, task_id: &TaskId) -> Option<&str> {
        self.ids.get(task_id).map(String::as_str)
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

fn validate_heading(heading: &str) -> Result<()> {
    if heading.is_empty() || heading.contains(['\r', '\n']) {
        bail!("list display name cannot be empty or contain a newline");
    }
    Ok(())
}

fn validate_summary(summary: &str) -> Result<()> {
    if summary.is_empty() {
        bail!("task summary cannot be empty");
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
