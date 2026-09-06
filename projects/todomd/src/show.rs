use std::{
    io::{self, Write},
    path::PathBuf,
};

use anyhow::{Context, Result};
use serde::Serialize;

use crate::{
    config::Config,
    repository::{load_lists, resolve_lists},
};

/// One active task, with the source file an external tool would edit.
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ShownTask {
    pub list: String,
    pub uid: String,
    pub summary: String,
    pub completed: bool,
    pub file: PathBuf,
}

/// Prints the active tasks of the selected lists as JSON.
pub fn run(config: &Config, requested_lists: &[String]) -> Result<()> {
    let lists = resolve_lists(config, requested_lists)?;
    let json = to_json(&collect(config, &lists)?)?;
    let mut stdout = io::stdout().lock();
    stdout
        .write_all(json.as_bytes())
        .context("failed to write tasks")?;
    stdout.flush().context("failed to flush tasks")
}

pub fn collect(config: &Config, lists: &[String]) -> Result<Vec<ShownTask>> {
    let (state, sources) = load_lists(config, lists)?;
    let mut shown = Vec::new();

    for list in &state.lists {
        for task in &list.tasks {
            let file = sources
                .task_files
                .get(&task.id)
                .with_context(|| format!("VTODO {:?} has no source file", task.id.as_str()))?;
            shown.push(ShownTask {
                list: list.name.clone(),
                uid: task.id.as_str().to_owned(),
                summary: task.summary.clone(),
                completed: task.completed,
                file: file.clone(),
            });
        }
    }

    Ok(shown)
}

pub fn to_json(tasks: &[ShownTask]) -> Result<String> {
    let mut json = serde_json::to_string_pretty(tasks).context("failed to serialize tasks")?;
    json.push('\n');
    Ok(json)
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    fn fixture_config() -> Config {
        Config::new(vec![
            Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/calendars"),
        ])
        .unwrap()
    }

    #[test]
    fn reports_active_tasks_with_their_source_files() {
        let config = fixture_config();

        let shown = collect(&config, &["Postgrad".to_owned(), "Personal".to_owned()]).unwrap();

        assert_eq!(shown.len(), 2);
        assert_eq!(shown[0].list, "Postgrad");
        assert_eq!(shown[0].uid, "write@example.test");
        assert_eq!(shown[0].summary, "Write paper draft");
        assert!(!shown[0].completed);
        assert!(shown[0].file.ends_with("Postgrad/write.ics"));
        assert_eq!(shown[1].list, "Personal");
        assert!(shown[1].file.ends_with("Personal/groceries.ics"));
    }

    #[test]
    fn serializes_an_empty_selection_as_an_empty_array() {
        assert_eq!(to_json(&[]).unwrap(), "[]\n");
    }

    #[test]
    fn serializes_documented_fields() {
        let config = fixture_config();

        let shown = collect(&config, &["Postgrad".to_owned()]).unwrap();
        let json: serde_json::Value = serde_json::from_str(&to_json(&shown).unwrap()).unwrap();

        let task = &json[0];
        assert_eq!(task["list"], "Postgrad");
        assert_eq!(task["uid"], "write@example.test");
        assert_eq!(task["summary"], "Write paper draft");
        assert_eq!(task["completed"], false);
        assert!(
            task["file"]
                .as_str()
                .unwrap()
                .ends_with("Postgrad/write.ics")
        );
    }
}
