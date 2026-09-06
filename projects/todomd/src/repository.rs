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

impl SourceSnapshot {
    pub fn file_for_task(&self, task_id: &TaskId) -> Option<&SourceFile> {
        let path = self.task_files.get(task_id)?;
        self.files.iter().find(|source| &source.path == path)
    }
}

pub fn verify_snapshot(snapshot: &SourceSnapshot) -> Result<()> {
    for (list_name, list_dir) in &snapshot.list_dirs {
        let displayname_path = list_dir.join("displayname");
        let metadata = fs::symlink_metadata(&displayname_path)
            .with_context(|| format!("failed to inspect {}", displayname_path.display()))?;
        if !metadata.file_type().is_file() {
            bail!("{} is not a regular file", displayname_path.display());
        }
        let current_name = fs::read_to_string(&displayname_path)
            .with_context(|| format!("failed to read {}", displayname_path.display()))?;
        if current_name.trim_end_matches(['\r', '\n']) != list_name {
            bail!("source list at {} changed identity", list_dir.display());
        }

        let expected = snapshot
            .files
            .iter()
            .filter(|source| &source.list_name == list_name)
            .map(|source| (source.path.clone(), source.sha256))
            .collect::<BTreeMap<_, _>>();
        let current_paths = ics_files(list_dir)?;
        let current_set = current_paths.iter().cloned().collect::<BTreeSet<_>>();
        let expected_set = expected.keys().cloned().collect::<BTreeSet<_>>();
        if current_set != expected_set {
            bail!("source list {list_name:?} changed after staging");
        }

        for path in current_paths {
            let bytes =
                fs::read(&path).with_context(|| format!("failed to verify {}", path.display()))?;
            let hash: [u8; 32] = Sha256::digest(bytes).into();
            if expected.get(&path) != Some(&hash) {
                bail!("source file {} changed after staging", path.display());
            }
        }
    }

    Ok(())
}

pub fn list_names(config: &Config) -> Result<Vec<String>> {
    let discovered = discover_lists(config)?;
    if discovered.is_empty() {
        bail!("no VTODO lists were found in the configured calendar roots");
    }
    Ok(discovered.into_keys().collect())
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
        let root = fs::canonicalize(root)
            .with_context(|| format!("failed to resolve calendar root {}", root.display()))?;
        let entries = fs::read_dir(&root)
            .with_context(|| format!("failed to read calendar root {}", root.display()))?;

        for entry in entries {
            let entry = entry
                .with_context(|| format!("failed to inspect calendar root {}", root.display()))?;
            let file_type = entry.file_type().with_context(|| {
                format!(
                    "failed to inspect calendar entry {}",
                    entry.path().display()
                )
            })?;
            if !file_type.is_dir() {
                continue;
            }
            let path = entry.path();

            let displayname_path = path.join("displayname");
            let displayname_type = match fs::symlink_metadata(&displayname_path) {
                Ok(metadata) => metadata.file_type(),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => {
                    return Err(error).with_context(|| {
                        format!("failed to inspect {}", displayname_path.display())
                    });
                }
            };
            if !displayname_type.is_file() {
                bail!("{} is not a regular file", displayname_path.display());
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
    let entries = fs::read_dir(list_dir)
        .with_context(|| format!("failed to read VTODO list {}", list_dir.display()))?;
    let mut paths = Vec::new();

    for entry in entries {
        let entry = entry
            .with_context(|| format!("failed to inspect VTODO list {}", list_dir.display()))?;
        let path = entry.path();
        if !path
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("ics"))
        {
            continue;
        }
        let file_type = entry
            .file_type()
            .with_context(|| format!("failed to inspect {}", path.display()))?;
        if !file_type.is_file() {
            bail!("VTODO path {} is not a regular file", path.display());
        }
        paths.push(path);
    }

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

    #[cfg(unix)]
    #[test]
    fn rejects_symlinked_ics_files() {
        use std::os::unix::fs::symlink;

        let directory = tempfile::tempdir().unwrap();
        let outside = directory.path().join("outside");
        let list = directory.path().join("list");
        fs::create_dir(&outside).unwrap();
        fs::create_dir(&list).unwrap();
        fs::write(outside.join("task.ics"), "not followed").unwrap();
        symlink(outside.join("task.ics"), list.join("task.ics")).unwrap();

        assert!(ics_files(&list).is_err());
    }

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
