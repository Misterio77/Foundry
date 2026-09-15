use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use icalendar::parser::{Component, Property, read_calendar, unfold};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    config::Config,
    dates::{self, DateContext, DateValue},
    model::{Priority, Task, TaskId, TaskList, TaskState},
};

/// Which tasks a command operates on.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub enum Scope {
    /// Active-root trees, stopping below any completed descendant.
    #[default]
    Active,
    /// Every task, including completed and cancelled ones.
    All,
}

#[derive(Clone, Debug)]
pub struct SourceFile {
    pub list_name: String,
    pub contents: String,
    pub sha256: [u8; 32],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ListColor {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

#[derive(Clone, Debug, Default)]
pub struct SourceSnapshot {
    pub list_dirs: BTreeMap<String, PathBuf>,
    pub files: BTreeMap<PathBuf, SourceFile>,
    pub task_files: BTreeMap<TaskId, PathBuf>,
    /// In-scope VTODOs with no summary to render. `SUMMARY` is optional in
    /// RFC 5545, so these are valid but cannot appear in the document.
    pub unrepresentable: Vec<PathBuf>,
}

impl SourceSnapshot {
    pub(crate) fn file_for_task(&self, task_id: &TaskId) -> Option<(&Path, &SourceFile)> {
        let path = self.task_files.get(task_id)?;
        Some((path, self.files.get(path)?))
    }

    pub(crate) fn file_hashes(&self) -> BTreeMap<PathBuf, [u8; 32]> {
        self.files
            .iter()
            .map(|(path, source)| (path.clone(), source.sha256))
            .collect()
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
            .filter(|(_, source)| &source.list_name == list_name)
            .map(|(path, source)| (path.clone(), source.sha256))
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

pub fn list_colors(
    config: &Config,
    requested_lists: &[String],
) -> Result<BTreeMap<String, ListColor>> {
    let discovered = discover_lists(config)?;
    let mut colors = BTreeMap::new();

    for requested in requested_lists {
        let list_dir = resolve_list_dir(&discovered, requested)?;
        let color_path = list_dir.join("color");
        let contents = match fs::read_to_string(&color_path) {
            Ok(contents) => contents,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to read {}", color_path.display()));
            }
        };
        let color = parse_list_color(contents.trim()).with_context(|| {
            format!(
                "invalid color metadata for list {requested:?} at {}",
                color_path.display()
            )
        })?;
        colors.insert(requested.clone(), color);
    }

    Ok(colors)
}

pub fn load_lists(
    config: &Config,
    requested_lists: &[String],
    scope: Scope,
) -> Result<(TaskState, SourceSnapshot)> {
    let discovered = discover_lists(config)?;
    let mut state = TaskState { lists: Vec::new() };
    let mut snapshot = SourceSnapshot::default();
    let date_context = DateContext::local_now()?;
    let mut seen_task_ids = BTreeSet::new();

    for requested in requested_lists {
        let list_dir = resolve_list_dir(&discovered, requested)?;

        snapshot
            .list_dirs
            .insert(requested.clone(), list_dir.to_path_buf());
        let mut loaded = BTreeMap::new();

        for path in ics_files(list_dir)? {
            let bytes =
                fs::read(&path).with_context(|| format!("failed to read {}", path.display()))?;
            let sha256 = Sha256::digest(&bytes).into();
            let contents = String::from_utf8(bytes)
                .with_context(|| format!("{} is not valid UTF-8", path.display()))?;
            let task = parse_task(&contents, &path, &date_context)?;
            snapshot.files.insert(
                path.clone(),
                SourceFile {
                    list_name: requested.clone(),
                    contents,
                    sha256,
                },
            );

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

fn resolve_list_dir<'a>(
    discovered: &'a BTreeMap<String, Vec<PathBuf>>,
    requested: &str,
) -> Result<&'a Path> {
    let matches = discovered
        .get(requested)
        .map(Vec::as_slice)
        .unwrap_or_default();
    match matches {
        [] => bail!("VTODO list {requested:?} was not found"),
        [path] => Ok(path),
        paths => {
            let locations = paths
                .iter()
                .map(|path| path.display().to_string())
                .collect::<Vec<_>>()
                .join(", ");
            bail!("VTODO list {requested:?} is ambiguous: {locations}");
        }
    }
}

fn parse_list_color(value: &str) -> Result<ListColor> {
    let hex = value
        .strip_prefix('#')
        .with_context(|| "expected #RRGGBB")?;
    if hex.len() != 6 || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("expected #RRGGBB");
    }
    let component = |start| u8::from_str_radix(&hex[start..start + 2], 16);
    Ok(ListColor {
        red: component(0)?,
        green: component(2)?,
        blue: component(4)?,
    })
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
        let hidden_completed_root =
            scope == Scope::Active && task.completed && task.parent.is_none();
        if task.summary.is_empty() {
            if !hidden_completed_root {
                snapshot.unrepresentable.push(path.clone());
            }
            return;
        }
        if hidden_completed_root {
            return;
        }

        snapshot.task_files.insert(task.id.clone(), path.clone());
        output.push(task.clone());
        if scope == Scope::Active && task.completed {
            return;
        }
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

fn parse_task(contents: &str, path: &Path, date_context: &DateContext) -> Result<Option<Task>> {
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
    let start = temporal_property(todo, "DTSTART", path, date_context)?;
    let due = temporal_property(todo, "DUE", path, date_context)?;
    let categories = category_properties(&unfolded, path)?;
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
            categories,
            parent,
            start,
            due,
        }));
    };

    Ok(Some(Task {
        id: TaskId::new(uid),
        summary,
        completed,
        priority,
        categories,
        parent,
        start,
        due,
    }))
}

fn category_properties(contents: &str, path: &Path) -> Result<Vec<String>> {
    let mut categories = BTreeSet::new();
    let mut in_todo = false;
    let mut depth = 0usize;

    for line in contents.lines() {
        if !in_todo {
            if line.eq_ignore_ascii_case("BEGIN:VTODO") {
                in_todo = true;
                depth = 1;
            }
            continue;
        }
        if line
            .split_once(':')
            .is_some_and(|(kind, _)| kind.eq_ignore_ascii_case("BEGIN"))
        {
            depth += 1;
            continue;
        }
        if line
            .split_once(':')
            .is_some_and(|(kind, _)| kind.eq_ignore_ascii_case("END"))
        {
            depth -= 1;
            if depth == 0 {
                break;
            }
            continue;
        }
        if depth != 1 {
            continue;
        }
        let Some((header, value)) = line.split_once(':') else {
            continue;
        };
        if !header
            .split(';')
            .next()
            .is_some_and(|name| name.eq_ignore_ascii_case("CATEGORIES"))
        {
            continue;
        }
        for category in split_category_values(value) {
            let category = category
                .with_context(|| format!("invalid CATEGORIES property in {}", path.display()))?;
            // Some clients emit an empty CATEGORIES property to represent an
            // empty set. Empty members are therefore harmless rather than an
            // unrenderable task.
            if category.is_empty() {
                continue;
            }
            if category.contains(['\r', '\n']) {
                bail!("VTODO in {} contains a multiline category", path.display());
            }
            categories.insert(category);
        }
    }

    Ok(categories.into_iter().collect())
}

fn split_category_values(value: &str) -> Vec<Result<String>> {
    let mut values = Vec::new();
    let mut current = String::new();
    let mut characters = value.chars();
    while let Some(character) = characters.next() {
        match character {
            ',' => values.push(Ok(std::mem::take(&mut current))),
            '\\' => match characters.next() {
                Some('n' | 'N') => current.push('\n'),
                Some(escaped @ (',' | ';' | '\\')) => current.push(escaped),
                Some(other) => {
                    current.push('\\');
                    current.push(other);
                }
                None => values.push(Err(anyhow::anyhow!("trailing escape in category value"))),
            },
            _ => current.push(character),
        }
    }
    values.push(Ok(current));
    values
}

fn temporal_property(
    component: &Component<'_>,
    name: &str,
    path: &Path,
    date_context: &DateContext,
) -> Result<Option<DateValue>> {
    let Some(property) = component_property(component, name, path)? else {
        return Ok(None);
    };
    dates::parse_ics(
        property.val.as_str(),
        property_parameter(property, "VALUE", name, path)?,
        property_parameter(property, "TZID", name, path)?,
        date_context,
    )
    .with_context(|| format!("invalid {name} in {}", path.display()))
    .map(Some)
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
    Ok(component_property(component, name, path)?.map(|property| property.val.as_str().to_owned()))
}

fn component_property<'a>(
    component: &'a Component<'_>,
    name: &str,
    path: &Path,
) -> Result<Option<&'a Property<'a>>> {
    let mut properties = component
        .properties
        .iter()
        .filter(|property| property.name.as_str().eq_ignore_ascii_case(name));
    let property = properties.next();
    if properties.next().is_some() {
        bail!(
            "VTODO in {} contains more than one {name} property",
            path.display()
        );
    }
    Ok(property)
}

fn property_parameter<'a>(
    property: &'a Property<'_>,
    parameter_name: &str,
    property_name: &str,
    path: &Path,
) -> Result<Option<&'a str>> {
    let mut values = property
        .params
        .iter()
        .filter(|parameter| parameter.key.as_str().eq_ignore_ascii_case(parameter_name))
        .filter_map(|parameter| parameter.val.as_ref().map(|value| value.as_str()));
    let value = values.next();
    if values.next().is_some() {
        bail!(
            "VTODO in {} contains more than one {parameter_name} parameter on {property_name}",
            path.display()
        );
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use super::*;

    fn date_context() -> DateContext {
        DateContext::in_timezone(
            "America/Sao_Paulo",
            Utc.with_ymd_and_hms(2026, 9, 7, 12, 0, 0).unwrap(),
        )
        .unwrap()
    }

    #[test]
    fn parses_vdir_list_colors() {
        assert_eq!(
            parse_list_color("#3366aA").unwrap(),
            ListColor {
                red: 0x33,
                green: 0x66,
                blue: 0xaa,
            }
        );
        assert!(parse_list_color("3366aa").is_err());
        assert!(parse_list_color("#3366").is_err());
        assert!(parse_list_color("#3366xx").is_err());
    }

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
        assert!(
            parse_task(event, Path::new("event.ics"), &date_context())
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn rejects_multiple_todos() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:a\r\nSUMMARY:A\r\nEND:VTODO\r\nBEGIN:VTODO\r\nUID:b\r\nSUMMARY:B\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        assert!(parse_task(calendar, Path::new("multiple.ics"), &date_context()).is_err());
    }

    #[test]
    fn parses_repeated_and_comma_separated_categories() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:tagged\r\nSUMMARY:Tagged\r\nCATEGORIES:Work,Quick Win\r\nCATEGORIES:comma\\,tag,semi\\;tag,slash\\\\tag\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("tagged.ics"), &date_context())
            .unwrap()
            .unwrap();

        assert_eq!(
            task.categories,
            ["Quick Win", "Work", "comma,tag", "semi;tag", "slash\\tag"]
        );
    }

    #[test]
    fn accepts_empty_category_properties() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:tagged\r\nSUMMARY:Tagged\r\nCATEGORIES:\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("tagged.ics"), &date_context())
            .unwrap()
            .unwrap();

        assert!(task.categories.is_empty());
    }

    #[test]
    fn rejects_invalid_categories() {
        for value in ["trailing\\", "line\\nfeed"] {
            let calendar = format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:tagged\r\nSUMMARY:Tagged\r\nCATEGORIES:{value}\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
            );
            assert!(parse_task(&calendar, Path::new("tagged.ics"), &date_context()).is_err());
        }
    }

    #[test]
    fn category_scanning_handles_mixed_case_component_boundaries() {
        let calendar = "BEGIN:VCALENDAR\r\nbegin:vtodo\r\nUID:tagged\r\nSUMMARY:Tagged\r\nbegin:valarm\r\nCATEGORIES:Nested\r\nend:valarm\r\nCATEGORIES:Direct\r\nend:vtodo\r\nEND:VCALENDAR\r\n";

        assert_eq!(
            category_properties(&unfold(calendar), Path::new("tagged.ics")).unwrap(),
            ["Direct"]
        );
    }

    #[test]
    fn parses_completed_todos_without_summaries_for_tree_projection() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:done\r\nSTATUS:COMPLETED\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("done.ics"), &date_context())
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
            let task = parse_task(calendar, Path::new("open.ics"), &date_context())
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
        write_todo(&list, "active", Some("Active parent"), None, None);
        write_todo(
            &list,
            "done-child",
            Some("Done child"),
            Some("COMPLETED"),
            Some("active"),
        );
        write_todo(
            &list,
            "active-grandchild",
            Some("Active grandchild"),
            None,
            Some("done-child"),
        );
        let config = Config::new(vec![directory.path().to_path_buf()]).unwrap();

        let (active, active_sources) =
            load_lists(&config, &["Work".to_owned()], Scope::Active).unwrap();
        assert_eq!(
            active.lists[0]
                .tasks
                .iter()
                .map(|task| task.id.as_str())
                .collect::<Vec<_>>(),
            ["active", "done-child"]
        );
        assert_eq!(active_sources.unrepresentable.len(), 1);

        let (all, all_sources) = load_lists(&config, &["Work".to_owned()], Scope::All).unwrap();
        assert_eq!(
            all.lists[0]
                .tasks
                .iter()
                .map(|task| task.id.as_str())
                .collect::<Vec<_>>(),
            [
                "active",
                "done-child",
                "active-grandchild",
                "done",
                "active-child",
            ]
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
            let task = parse_task(&calendar, Path::new("child.ics"), &date_context())
                .unwrap()
                .unwrap();
            assert_eq!(task.parent.as_ref().map(TaskId::as_str), Some("parent"));
        }

        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:child\r\nSUMMARY:Child\r\nRELATED-TO;RELTYPE=SIBLING:peer\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let task = parse_task(calendar, Path::new("child.ics"), &date_context())
            .unwrap()
            .unwrap();
        assert_eq!(task.parent, None);
    }

    #[test]
    fn rejects_conflicting_parent_relationships() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:child\r\nSUMMARY:Child\r\nRELATED-TO:a\r\nRELATED-TO;RELTYPE=PARENT:b\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let error = parse_task(calendar, Path::new("child.ics"), &date_context()).unwrap_err();

        assert!(error.to_string().contains("conflicting RELATED-TO parents"));
    }

    #[test]
    fn reads_date_and_timezone_aware_datetime_properties() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:dated\r\nSUMMARY:Dated\r\nDTSTART;TZID=Europe/London:20260907T100042\r\nDUE;VALUE=DATE:20260908\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("dated.ics"), &date_context())
            .unwrap()
            .unwrap();

        assert_eq!(task.start.unwrap().canonical(), "2026-09-07 06:00");
        assert_eq!(task.due.unwrap().canonical(), "2026-09-08");
    }

    #[test]
    fn rejects_duplicate_date_properties() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:dated\r\nSUMMARY:Dated\r\nDUE;VALUE=DATE:20260908\r\nDUE;VALUE=DATE:20260909\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let error = parse_task(calendar, Path::new("dated.ics"), &date_context()).unwrap_err();

        assert!(error.to_string().contains("more than one DUE"));
    }

    #[test]
    fn rejects_duplicate_date_parameters() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:dated\r\nSUMMARY:Dated\r\nDUE;VALUE=DATE;VALUE=DATE:20260908\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let error = parse_task(calendar, Path::new("dated.ics"), &date_context()).unwrap_err();

        assert!(error.to_string().contains("more than one VALUE parameter"));
    }

    #[test]
    fn recognizes_completed_and_cancelled_tasks() {
        for status in ["COMPLETED", "CANCELLED"] {
            let calendar = format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:done\r\nSTATUS:{status}\r\nSUMMARY:Done\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
            );

            let task = parse_task(&calendar, Path::new("done.ics"), &date_context())
                .unwrap()
                .unwrap();
            assert!(task.completed);
            assert_eq!(task.summary, "Done");
        }
    }

    #[test]
    fn keeps_in_process_tasks_active() {
        let calendar = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:doing\r\nSTATUS:IN-PROCESS\r\nSUMMARY:Doing\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

        let task = parse_task(calendar, Path::new("doing.ics"), &date_context())
            .unwrap()
            .unwrap();

        assert!(!task.completed);
    }
}
