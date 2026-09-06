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
    model::{Priority, Task, TaskId, TaskList, TaskState},
};

/// Which tasks a command operates on.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Scope {
    /// Tasks that are neither completed nor cancelled.
    #[default]
    Active,
    /// Every task, including completed and cancelled ones.
    All,
}

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
    /// In-scope VTODOs with no summary to render. `SUMMARY` is optional in
    /// RFC 5545, so these are valid but cannot appear in the document.
    pub unrepresentable: Vec<PathBuf>,
}

impl SourceSnapshot {
    pub fn file_for_task(&self, task_id: &TaskId) -> Option<&SourceFile> {
        let path = self.task_files.get(task_id)?;
        self.files.iter().find(|source| &source.path == path)
    }

    /// Describes in-scope tasks left out of the document, so that they are
    /// never omitted silently.
    pub fn unrepresentable_warning(&self) -> Option<String> {
        let (first, rest) = self.unrepresentable.split_first()?;
        let count = self.unrepresentable.len();
        let tasks = if count == 1 { "task" } else { "tasks" };
        let more = match rest.len() {
            0 => String::new(),
            remaining => format!(", and {remaining} more"),
        };
        Some(format!(
            "{count} {tasks} without a summary not shown: {}{more}",
            first.display()
        ))
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

/// Resolves the lists a command operates on, defaulting to every discovered
/// list in display-name order.
pub fn resolve_lists(config: &Config, requested_lists: &[String]) -> Result<Vec<String>> {
    if requested_lists.is_empty() {
        return list_names(config);
    }

    let unique = requested_lists.iter().collect::<BTreeSet<_>>();
    if unique.len() != requested_lists.len() {
        bail!("list names must not be repeated");
    }

    Ok(requested_lists.to_vec())
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
    scope: Scope,
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
        let mut loaded = BTreeMap::new();

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
            loaded.insert(task.id.clone(), (task, path));
        }

        let tasks = project_tasks(loaded, scope, &mut snapshot)
            .with_context(|| format!("invalid task hierarchy in list {requested:?}"))?;
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

type LoadedTasks = BTreeMap<TaskId, (Task, PathBuf)>;

fn task_order(left: &Task, right: &Task) -> std::cmp::Ordering {
    left.completed
        .cmp(&right.completed)
        .then_with(|| right.priority.cmp(&left.priority))
        .then_with(|| {
            left.summary
                .to_lowercase()
                .cmp(&right.summary.to_lowercase())
        })
        .then_with(|| left.id.cmp(&right.id))
}

fn project_tasks(
    mut loaded: LoadedTasks,
    scope: Scope,
    snapshot: &mut SourceSnapshot,
) -> Result<Vec<Task>> {
    let ids = loaded.keys().cloned().collect::<BTreeSet<_>>();
    for (task, _) in loaded.values_mut() {
        if task
            .parent
            .as_ref()
            .is_some_and(|parent| !ids.contains(parent))
        {
            // Empty and dangling relationships are top-level in Markdown. The
            // raw property remains in SourceSnapshot and is not rewritten.
            task.parent = None;
        }
    }
    validate_acyclic(&loaded)?;

    let mut children: BTreeMap<Option<TaskId>, Vec<TaskId>> = BTreeMap::new();
    for task in loaded.values().map(|(task, _)| task) {
        children
            .entry(task.parent.clone())
            .or_default()
            .push(task.id.clone());
    }
    for siblings in children.values_mut() {
        siblings.sort_by(|left, right| task_order(&loaded[left].0, &loaded[right].0));
    }

    fn append_subtree(
        id: &TaskId,
        loaded: &LoadedTasks,
        children: &BTreeMap<Option<TaskId>, Vec<TaskId>>,
        scope: Scope,
        snapshot: &mut SourceSnapshot,
        output: &mut Vec<Task>,
    ) {
        let (task, path) = &loaded[id];
        let hidden_by_scope = scope == Scope::Active && task.completed;
        if hidden_by_scope || task.summary.is_empty() {
            if task.summary.is_empty() && !hidden_by_scope {
                snapshot.unrepresentable.push(path.clone());
            }
            return;
        }

        snapshot.task_files.insert(task.id.clone(), path.clone());
        output.push(task.clone());
        if let Some(descendants) = children.get(&Some(task.id.clone())) {
            for child in descendants {
                append_subtree(child, loaded, children, scope, snapshot, output);
            }
        }
    }

    let mut output = Vec::new();
    if let Some(roots) = children.get(&None) {
        for root in roots {
            append_subtree(root, &loaded, &children, scope, snapshot, &mut output);
        }
    }
    Ok(output)
}

fn validate_acyclic(loaded: &LoadedTasks) -> Result<()> {
    for start in loaded.keys() {
        let mut path = Vec::new();
        let mut positions = BTreeMap::new();
        let mut current = Some(start);
        while let Some(id) = current {
            if let Some(index) = positions.insert(id, path.len()) {
                let mut cycle = path[index..]
                    .iter()
                    .map(|id: &&TaskId| format!("{:?}", id.as_str()))
                    .collect::<Vec<_>>();
                cycle.push(format!("{:?}", id.as_str()));
                bail!("RELATED-TO cycle: {}", cycle.join(" -> "));
            }
            path.push(id);
            current = loaded[id].0.parent.as_ref();
        }
    }
    Ok(())
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
    let completed = status.as_deref().is_some_and(|status| {
        status.eq_ignore_ascii_case("COMPLETED") || status.eq_ignore_ascii_case("CANCELLED")
    });
    let uid = required_property(todo, "UID", path)?;
    let priority = optional_property(todo, "PRIORITY", path)?
        .map(|value| Priority::from_ics(&value))
        .unwrap_or_default();
    let parent = parent_property(todo, path)?.map(TaskId::new);
    // SUMMARY is optional in RFC 5545, so a task without one is valid but has
    // nothing to render. Every scope skips it and reports it instead.
    let Some(summary) =
        optional_property(todo, "SUMMARY", path)?.filter(|summary| !summary.trim().is_empty())
    else {
        return Ok(Some(Task {
            id: TaskId::new(uid),
            summary: String::new(),
            completed,
            priority,
            parent,
        }));
    };

    Ok(Some(Task {
        id: TaskId::new(uid),
        summary,
        completed,
        priority,
        parent,
    }))
}

fn parent_property(component: &Component<'_>, path: &Path) -> Result<Option<String>> {
    let values = component
        .properties
        .iter()
        .filter(|property| {
            property.name.as_str().eq_ignore_ascii_case("RELATED-TO")
                && property.params.iter().all(|parameter| {
                    !parameter.key.as_str().eq_ignore_ascii_case("RELTYPE")
                        || parameter
                            .val
                            .as_ref()
                            .is_some_and(|value| value.as_str().eq_ignore_ascii_case("PARENT"))
                })
        })
        .map(|property| property.val.as_str().trim())
        .filter(|value| !value.is_empty())
        .collect::<BTreeSet<_>>();
    match values.len() {
        0 => Ok(None),
        1 => Ok(values.first().map(|value| (*value).to_owned())),
        _ => bail!(
            "VTODO in {} names conflicting RELATED-TO parents: {}",
            path.display(),
            values.into_iter().collect::<Vec<_>>().join(", ")
        ),
    }
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

    fn write_todo(
        list: &Path,
        uid: &str,
        summary: Option<&str>,
        status: Option<&str>,
        related_to: Option<&str>,
    ) {
        let summary = summary.map_or(String::new(), |value| format!("SUMMARY:{value}\r\n"));
        let status = status.map_or(String::new(), |value| format!("STATUS:{value}\r\n"));
        let related_to =
            related_to.map_or(String::new(), |value| format!("RELATED-TO:{value}\r\n"));
        fs::write(
            list.join(format!("{uid}.ics")),
            format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:{uid}\r\n{summary}{status}{related_to}END:VTODO\r\nEND:VCALENDAR\r\n"
            ),
        )
        .unwrap();
    }

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
    fn parses_completed_todos_without_summaries_for_tree_projection() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:done\r\nSTATUS:COMPLETED\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("done.ics"))
            .unwrap()
            .unwrap();
        assert!(task.completed);
        assert!(task.summary.is_empty());
    }

    #[test]
    fn skips_todos_without_a_summary_in_every_scope() {
        // SUMMARY is optional in RFC 5545: valid, but nothing to render.
        let missing =
            "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:open\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let blank = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:open\r\nSUMMARY:   \r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        for calendar in [missing, blank] {
            let task = parse_task(calendar, Path::new("open.ics"))
                .unwrap()
                .unwrap();
            assert!(task.summary.is_empty());
        }
    }

    #[test]
    fn sorts_by_status_then_priority_then_name() {
        let directory = tempfile::tempdir().unwrap();
        let list = directory.path().join("list");
        fs::create_dir(&list).unwrap();
        fs::write(list.join("displayname"), "Work\n").unwrap();

        for (uid, summary, priority, done) in [
            ("a", "zulu", Some("1"), false),
            ("b", "alpha", None, false),
            ("c", "Bravo", Some("9"), false),
            ("d", "alpha", Some("1"), false),
            ("e", "mike", Some("5"), false),
            ("f", "delta", Some("4"), false),
            ("g", "aardvark", Some("1"), true),
            ("h", "yankee", None, true),
        ] {
            let priority = priority.map_or(String::new(), |value| format!("PRIORITY:{value}\r\n"));
            let status = if done {
                "STATUS:COMPLETED\r\n"
            } else {
                "STATUS:NEEDS-ACTION\r\n"
            };
            fs::write(
                list.join(format!("{uid}.ics")),
                format!(
                    "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:{uid}\r\nSUMMARY:{summary}\r\n{priority}{status}END:VTODO\r\nEND:VCALENDAR\r\n"
                ),
            )
            .unwrap();
        }

        let config = Config::new(vec![directory.path().to_path_buf()]).unwrap();
        let (state, _) = load_lists(&config, &["Work".to_owned()], Scope::All).unwrap();

        let order = state.lists[0]
            .tasks
            .iter()
            .map(|task| (task.completed, task.priority, task.summary.as_str()))
            .collect::<Vec<_>>();
        assert_eq!(
            order,
            [
                // 1 and 4 both read as high, so they interleave alphabetically.
                (false, Priority::High, "alpha"),
                (false, Priority::High, "delta"),
                (false, Priority::High, "zulu"),
                (false, Priority::Medium, "mike"),
                (false, Priority::Low, "Bravo"),
                (false, Priority::None, "alpha"),
                // Finished tasks sink below every unfinished one.
                (true, Priority::High, "aardvark"),
                (true, Priority::None, "yankee"),
            ]
        );
    }

    #[test]
    fn orders_each_sibling_set_beneath_its_parent() {
        let directory = tempfile::tempdir().unwrap();
        let list = directory.path().join("list");
        fs::create_dir(&list).unwrap();
        fs::write(list.join("displayname"), "Work\n").unwrap();
        write_todo(&list, "root", Some("Root"), None, None);
        write_todo(&list, "z", Some("Zulu child"), None, Some("root"));
        write_todo(&list, "a", Some("Alpha child"), None, Some("root"));
        write_todo(&list, "grand", Some("Grandchild"), None, Some("a"));
        write_todo(&list, "dangling", Some("Dangling"), None, Some("missing"));
        write_todo(&list, "empty", Some("Empty relation"), None, Some(""));
        let config = Config::new(vec![directory.path().to_path_buf()]).unwrap();

        let (state, _) = load_lists(&config, &["Work".to_owned()], Scope::All).unwrap();
        let tasks = &state.lists[0].tasks;
        let order = tasks
            .iter()
            .map(|task| (task.id.as_str(), task.parent.as_ref().map(TaskId::as_str)))
            .collect::<Vec<_>>();

        assert_eq!(
            order,
            [
                ("dangling", None),
                ("empty", None),
                ("root", None),
                ("a", Some("root")),
                ("grand", Some("a")),
                ("z", Some("root")),
            ]
        );
    }

    #[test]
    fn hidden_parents_hide_their_descendant_subtrees() {
        let directory = tempfile::tempdir().unwrap();
        let list = directory.path().join("list");
        fs::create_dir(&list).unwrap();
        fs::write(list.join("displayname"), "Work\n").unwrap();
        write_todo(&list, "done", Some("Done parent"), Some("COMPLETED"), None);
        write_todo(
            &list,
            "active-child",
            Some("Active child"),
            None,
            Some("done"),
        );
        write_todo(&list, "blank", None, None, None);
        write_todo(
            &list,
            "blank-child",
            Some("Hidden child"),
            None,
            Some("blank"),
        );
        let config = Config::new(vec![directory.path().to_path_buf()]).unwrap();

        let (active, active_sources) =
            load_lists(&config, &["Work".to_owned()], Scope::Active).unwrap();
        assert!(active.lists[0].tasks.is_empty());
        assert_eq!(active_sources.unrepresentable.len(), 1);

        let (all, all_sources) = load_lists(&config, &["Work".to_owned()], Scope::All).unwrap();
        assert_eq!(
            all.lists[0]
                .tasks
                .iter()
                .map(|task| task.id.as_str())
                .collect::<Vec<_>>(),
            ["done", "active-child"]
        );
        assert_eq!(all_sources.unrepresentable.len(), 1);
    }

    #[test]
    fn rejects_related_to_cycles() {
        let directory = tempfile::tempdir().unwrap();
        let list = directory.path().join("list");
        fs::create_dir(&list).unwrap();
        fs::write(list.join("displayname"), "Work\n").unwrap();
        write_todo(&list, "a", Some("A"), None, Some("b"));
        write_todo(&list, "b", Some("B"), None, Some("a"));
        let config = Config::new(vec![directory.path().to_path_buf()]).unwrap();

        let error = load_lists(&config, &["Work".to_owned()], Scope::Active).unwrap_err();

        let message = format!("{error:#}");
        assert!(message.contains("RELATED-TO cycle"), "{message}");
        assert!(
            message.contains("\"a\" -> \"b\" -> \"a\"")
                || message.contains("\"b\" -> \"a\" -> \"b\""),
            "{message}"
        );
    }

    #[test]
    fn records_unrepresentable_tasks_instead_of_failing() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/calendars");
        let config = Config::new(vec![root]).unwrap();

        let (state, sources) =
            load_lists(&config, &["Postgrad".to_owned()], Scope::Active).unwrap();

        assert!(
            state.lists[0]
                .tasks
                .iter()
                .all(|task| !task.summary.is_empty())
        );
        assert_eq!(sources.unrepresentable.len(), 1);
        assert!(sources.unrepresentable[0].ends_with("Postgrad/nosummary.ics"));
        assert_eq!(
            sources.unrepresentable_warning().unwrap(),
            format!(
                "1 task without a summary not shown: {}",
                sources.unrepresentable[0].display()
            )
        );
    }

    #[test]
    fn summarizes_several_unrepresentable_tasks() {
        let snapshot = SourceSnapshot {
            unrepresentable: vec![
                PathBuf::from("/lists/a.ics"),
                PathBuf::from("/lists/b.ics"),
                PathBuf::from("/lists/c.ics"),
            ],
            ..SourceSnapshot::default()
        };

        assert_eq!(
            snapshot.unrepresentable_warning().unwrap(),
            "3 tasks without a summary not shown: /lists/a.ics, and 2 more"
        );
        assert!(
            SourceSnapshot::default()
                .unrepresentable_warning()
                .is_none()
        );
    }

    #[test]
    fn reads_bare_explicit_and_duplicate_parent_relationships() {
        for property in [
            "RELATED-TO:parent",
            "RELATED-TO;RELTYPE=PARENT:parent",
            "RELATED-TO:parent\r\nRELATED-TO;RELTYPE=PARENT:parent",
        ] {
            let calendar = format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:child\r\nSUMMARY:Child\r\n{property}\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
            );
            let task = parse_task(&calendar, Path::new("child.ics"))
                .unwrap()
                .unwrap();
            assert_eq!(task.parent.as_ref().map(TaskId::as_str), Some("parent"));
        }

        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:child\r\nSUMMARY:Child\r\nRELATED-TO;RELTYPE=SIBLING:peer\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let task = parse_task(calendar, Path::new("child.ics"))
            .unwrap()
            .unwrap();
        assert_eq!(task.parent, None);
    }

    #[test]
    fn rejects_conflicting_parent_relationships() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:child\r\nSUMMARY:Child\r\nRELATED-TO:a\r\nRELATED-TO;RELTYPE=PARENT:b\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let error = parse_task(calendar, Path::new("child.ics")).unwrap_err();

        assert!(error.to_string().contains("conflicting RELATED-TO parents"));
    }

    #[test]
    fn recognizes_completed_and_cancelled_tasks() {
        for status in ["COMPLETED", "CANCELLED"] {
            let calendar = format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:done\r\nSTATUS:{status}\r\nSUMMARY:Done\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
            );

            let task = parse_task(&calendar, Path::new("done.ics"))
                .unwrap()
                .unwrap();
            assert!(task.completed);
            assert_eq!(task.summary, "Done");
        }
    }

    #[test]
    fn keeps_in_process_tasks_active() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:doing\r\nSTATUS:IN-PROCESS\r\nSUMMARY:Doing\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("doing.ics"))
            .unwrap()
            .unwrap();

        assert!(!task.completed);
    }
}
