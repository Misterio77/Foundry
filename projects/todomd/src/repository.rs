use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use icalendar::parser::{Component, read_calendar, unfold};
use sha2::{Digest, Sha256};

use crate::{
    config::Config,
    model::{Task, TaskId, TaskList, TaskState},
};

#[derive(Clone, Debug)]
pub struct SourceFile {
    pub list_name: String,
    pub path: PathBuf,
    pub contents: String,
    pub sha256: [u8; 32],
}

#[derive(Clone, Debug, Default)]
pub struct SourceSnapshot {
    pub list_dirs: BTreeMap<String, PathBuf>,
    pub files: Vec<SourceFile>,
    pub task_files: BTreeMap<TaskId, PathBuf>,
}

pub fn load_lists(
    config: &Config,
    requested_lists: &[String],
) -> Result<(TaskState, SourceSnapshot)> {
    let discovered = discover_lists(config)?;
    let mut state = TaskState { lists: Vec::new() };
    let mut snapshot = SourceSnapshot::default();
    let mut seen_task_ids = BTreeSet::new();

    for requested in requested_lists {
        let matches = discovered.get(requested).cloned().unwrap_or_default();
        let list_dir = match matches.as_slice() {
            [] => bail!("VTODO list {requested:?} was not found"),
            [path] => path,
            paths => {
                let locations = paths
                    .iter()
                    .map(|path| path.display().to_string())
                    .collect::<Vec<_>>()
                    .join(", ");
                bail!("VTODO list {requested:?} is ambiguous: {locations}");
            }
        };

        snapshot
            .list_dirs
            .insert(requested.clone(), list_dir.clone());
        let mut tasks = Vec::new();

        for path in ics_files(list_dir)? {
            let bytes =
                fs::read(&path).with_context(|| format!("failed to read {}", path.display()))?;
            let sha256 = Sha256::digest(&bytes).into();
            let contents = String::from_utf8(bytes)
                .with_context(|| format!("{} is not valid UTF-8", path.display()))?;
            let task = parse_task(&contents, &path)?;
            snapshot.files.push(SourceFile {
                list_name: requested.clone(),
                path: path.clone(),
                contents,
                sha256,
            });

            let Some(task) = task else {
                continue;
            };

            if !seen_task_ids.insert(task.id.clone()) {
                bail!(
                    "duplicate VTODO UID {:?} in selected lists",
                    task.id.as_str()
                );
            }
            snapshot.task_files.insert(task.id.clone(), path);
            tasks.push(task);
        }

        tasks.sort_by(|left, right| {
            left.summary
                .to_lowercase()
                .cmp(&right.summary.to_lowercase())
                .then_with(|| left.id.cmp(&right.id))
        });
        state.lists.push(TaskList {
            name: requested.clone(),
            tasks,
        });
    }

    Ok((state, snapshot))
}

fn discover_lists(config: &Config) -> Result<BTreeMap<String, Vec<PathBuf>>> {
    let mut discovered: BTreeMap<String, Vec<PathBuf>> = BTreeMap::new();

    for root in &config.calendar_roots {
        let entries = fs::read_dir(root)
            .with_context(|| format!("failed to read calendar root {}", root.display()))?;

        for entry in entries {
            let entry = entry
                .with_context(|| format!("failed to inspect calendar root {}", root.display()))?;
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            let displayname_path = path.join("displayname");
            if !displayname_path.is_file() {
                continue;
            }
            let displayname = fs::read_to_string(&displayname_path)
                .with_context(|| format!("failed to read {}", displayname_path.display()))?;
            let displayname = displayname.trim_end_matches(['\r', '\n']);
            if displayname.is_empty() {
                bail!("list {} has an empty displayname", path.display());
            }
            discovered
                .entry(displayname.to_owned())
                .or_default()
                .push(path);
        }
    }

    Ok(discovered)
}

fn ics_files(list_dir: &Path) -> Result<Vec<PathBuf>> {
    let mut paths = fs::read_dir(list_dir)
        .with_context(|| format!("failed to read VTODO list {}", list_dir.display()))?
        .filter_map(|entry| match entry {
            Ok(entry)
                if entry.path().is_file()
                    && entry
                        .path()
                        .extension()
                        .is_some_and(|extension| extension.eq_ignore_ascii_case("ics")) =>
            {
                Some(Ok(entry.path()))
            }
            Ok(_) => None,
            Err(error) => Some(Err(error)),
        })
        .collect::<std::io::Result<Vec<_>>>()
        .with_context(|| format!("failed to inspect VTODO list {}", list_dir.display()))?;
    paths.sort();
    Ok(paths)
}

fn parse_task(contents: &str, path: &Path) -> Result<Option<Task>> {
    let unfolded = unfold(contents);
    let calendar = read_calendar(&unfolded)
        .map_err(anyhow::Error::msg)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    let todos = calendar
        .components
        .iter()
        .filter(|component| component.name.as_str().eq_ignore_ascii_case("VTODO"))
        .collect::<Vec<_>>();

    let todo = match todos.as_slice() {
        [] => return Ok(None),
        [todo] => *todo,
        _ => bail!("{} contains more than one VTODO", path.display()),
    };

    let status = optional_property(todo, "STATUS", path)?;
    if status.as_deref().is_some_and(|status| {
        status.eq_ignore_ascii_case("COMPLETED") || status.eq_ignore_ascii_case("CANCELLED")
    }) {
        return Ok(None);
    }

    let uid = required_property(todo, "UID", path)?;
    let summary = required_property(todo, "SUMMARY", path)?;

    Ok(Some(Task {
        id: TaskId::new(uid),
        summary,
        completed: false,
    }))
}

fn required_property(component: &Component<'_>, name: &str, path: &Path) -> Result<String> {
    optional_property(component, name, path)?.with_context(|| {
        format!(
            "VTODO in {} is missing required {name} property",
            path.display()
        )
    })
}

fn optional_property(component: &Component<'_>, name: &str, path: &Path) -> Result<Option<String>> {
    let values = component
        .properties
        .iter()
        .filter(|property| property.name.as_str().eq_ignore_ascii_case(name))
        .map(|property| property.val.as_str())
        .collect::<Vec<_>>();

    match values.as_slice() {
        [] => Ok(None),
        [value] => Ok(Some((*value).to_owned())),
        _ => bail!(
            "VTODO in {} contains more than one {name} property",
            path.display()
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ignores_non_todo_components() {
        let event =
            "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        assert!(parse_task(event, Path::new("event.ics")).unwrap().is_none());
    }

    #[test]
    fn rejects_multiple_todos() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:a\r\nSUMMARY:A\r\nEND:VTODO\r\nBEGIN:VTODO\r\nUID:b\r\nSUMMARY:B\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        assert!(parse_task(calendar, Path::new("multiple.ics")).is_err());
    }

    #[test]
    fn ignores_completed_todos_without_summaries() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:done\r\nSTATUS:COMPLETED\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        assert!(
            parse_task(calendar, Path::new("done.ics"))
                .unwrap()
                .is_none()
        );
    }
}
