use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::{
    dates::{self, DateContext, DateValue},
    model::{
        EditedTask, EditedTaskList, EditedTaskState, Priority, TaskId, TaskReference, TaskState,
    },
    view::{self, View},
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
    render_with_view(state, &View::default(), manifest)
}

pub fn render_with_view(
    state: &TaskState,
    active_view: &View,
    manifest: &mut IdentityManifest,
) -> Result<String> {
    let mut output = String::new();
    let mut previous_headings = Vec::<String>::new();
    let sole_list_selected = state.lists.len() == 1;

    for tree in view::project(state, active_view) {
        let common = previous_headings
            .iter()
            .zip(&tree.headings)
            .take_while(|(left, right)| left == right)
            .count();
        if common < tree.headings.len() {
            if !output.is_empty() {
                output.push('\n');
            }
            for (depth, heading) in tree.headings.iter().enumerate().skip(common) {
                validate_heading(heading)?;
                output.push_str(&"#".repeat(depth + 1));
                output.push(' ');
                output.push_str(heading);
                output.push_str("\n\n");
            }
        }
        previous_headings = tree.headings;

        for projected in tree.tasks {
            let task = projected.task;
            validate_summary(&task.summary)?;
            for category in &task.categories {
                validate_category(category)?;
            }
            let checked = if task.completed { 'x' } else { ' ' };
            let root = projected.depth == 0;
            let grouped = |key| root && active_view.group_by.contains(&key);
            let list = if root && !grouped(view::GroupKey::List) && !sole_list_selected {
                format!("{} ", render_list_marker(tree.list_name))
            } else {
                String::new()
            };
            let due = (!grouped(view::GroupKey::Due))
                .then_some(task.due.as_ref())
                .flatten()
                .map_or_else(String::new, |value| format!("-{} ", value.marker()));
            let start = (!grouped(view::GroupKey::Start))
                .then_some(task.start.as_ref())
                .flatten()
                .map_or_else(String::new, |value| format!("+{} ", value.marker()));
            let priority = if grouped(view::GroupKey::Priority) {
                String::new()
            } else {
                match task.priority.marker() {
                    "" => String::new(),
                    marker => format!("{marker} "),
                }
            };
            let categories = (!grouped(view::GroupKey::Categories))
                .then(|| render_categories(&task.categories))
                .flatten()
                .map(|field| format!("{field} "))
                .unwrap_or_default();
            let summary = render_summary(&task.summary);
            let session_id = manifest.get_or_insert(&task.id);
            output.push_str(&"  ".repeat(projected.depth));
            output.push_str(&format!(
                "- [{checked}] {list}{due}{start}{priority}{categories}{summary}{MARKER_START}{session_id}{MARKER_END}\n"
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
    parse_with_view(input, baseline, manifest, &View::default())
}

pub fn parse_with_view(
    input: &str,
    baseline: &TaskState,
    manifest: &IdentityManifest,
    active_view: &View,
) -> Result<EditedTaskState> {
    let expected_lists = baseline
        .lists
        .iter()
        .map(|list| list.name.as_str())
        .collect::<BTreeSet<_>>();
    let sole_list = (baseline.lists.len() == 1).then(|| baseline.lists[0].name.clone());
    let mut parsed_lists = baseline
        .lists
        .iter()
        .map(|list| (list.name.clone(), Vec::new()))
        .collect::<BTreeMap<String, Vec<EditedTask>>>();
    let mut seen_ids = BTreeSet::new();
    let mut ancestors: Vec<(TaskReference, String)> = Vec::new();
    let mut headings = Vec::<HeadingValue>::new();
    let mut next_draft_id = 1;
    let date_context = DateContext::local_now()?;

    for (index, line) in input.lines().enumerate() {
        let line_number = index + 1;
        if line.trim().is_empty() {
            continue;
        }

        if line.starts_with('#') {
            let hashes = line.bytes().take_while(|byte| *byte == b'#').count();
            if hashes == 0 || line.as_bytes().get(hashes) != Some(&b' ') || hashes > 6 {
                bail!("line {line_number}: malformed presentation heading");
            }
            if let Some(key) = active_view.group_by.get(hashes - 1) {
                if hashes > headings.len() + 1 {
                    bail!("line {line_number}: grouping heading skips a level");
                }
                headings.truncate(hashes - 1);
                headings.push(
                    parse_heading_value(*key, &line[hashes + 1..], &expected_lists, &date_context)
                        .with_context(|| format!("line {line_number}"))?,
                );
            }
            continue;
        }

        let (depth, task_line) = split_indentation(line, line_number)?;
        if depth > ancestors.len() {
            bail!("line {line_number}: task nesting jumps more than one level");
        }
        let (mut task, explicit) =
            parse_task_line(task_line, line_number, manifest, &date_context)?;
        let list_name = if depth == 0 {
            if headings.len() < active_view.group_by.len() {
                bail!("line {line_number}: root task is missing its grouping heading");
            }
            apply_heading_values(&mut task, &explicit, &headings);
            explicit
                .list
                .clone()
                .or_else(|| heading_list(&headings).map(str::to_owned))
                .or_else(|| sole_list.clone())
                .with_context(|| {
                    format!(
                        "line {line_number}: a root task must contain an @list marker when editing multiple lists without list grouping"
                    )
                })?
        } else {
            if explicit.list.is_some() {
                bail!("line {line_number}: a child task must inherit its parent's list");
            }
            ancestors[depth - 1].1.clone()
        };
        if !expected_lists.contains(list_name.as_str()) {
            bail!("line {line_number}: unknown list {list_name:?}");
        }
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
        task.parent = depth.checked_sub(1).map(|index| ancestors[index].0.clone());
        ancestors.truncate(depth);
        ancestors.push((task_reference, list_name.clone()));
        parsed_lists
            .get_mut(&list_name)
            .expect("selected list was prepopulated")
            .push(task);
    }

    let lists = baseline
        .lists
        .iter()
        .map(|list| EditedTaskList {
            name: list.name.clone(),
            tasks: parsed_lists
                .remove(&list.name)
                .expect("selected list was prepopulated"),
        })
        .collect();

    Ok(EditedTaskState { lists })
}

#[derive(Clone, Debug)]
enum HeadingValue {
    List(String),
    Completed,
    Priority(Priority),
    Due(Option<DateValue>),
    Start(Option<DateValue>),
    Categories(Vec<String>),
}

fn parse_heading_value(
    key: view::GroupKey,
    label: &str,
    expected_lists: &BTreeSet<&str>,
    date_context: &DateContext,
) -> Result<HeadingValue> {
    match key {
        view::GroupKey::List => {
            if !expected_lists.contains(label) {
                bail!("unknown list grouping {label:?}");
            }
            Ok(HeadingValue::List(label.to_owned()))
        }
        view::GroupKey::Completed => match label {
            "Incomplete" | "Completed" => Ok(HeadingValue::Completed),
            _ => bail!("unknown completion grouping {label:?}"),
        },
        view::GroupKey::Priority => match label {
            "High priority" => Ok(HeadingValue::Priority(Priority::High)),
            "Medium priority" => Ok(HeadingValue::Priority(Priority::Medium)),
            "Low priority" => Ok(HeadingValue::Priority(Priority::Low)),
            "No priority" => Ok(HeadingValue::Priority(Priority::None)),
            _ => bail!("unknown priority grouping {label:?}"),
        },
        view::GroupKey::Due => Ok(HeadingValue::Due(parse_heading_date(
            label,
            "No due date",
            date_context,
        )?)),
        view::GroupKey::Start => Ok(HeadingValue::Start(parse_heading_date(
            label,
            "No start date",
            date_context,
        )?)),
        view::GroupKey::Categories => {
            if label == "No categories" {
                return Ok(HeadingValue::Categories(Vec::new()));
            }
            let (categories, remainder) = take_categories(label)?;
            if !remainder.is_empty() {
                bail!("invalid categories grouping {label:?}");
            }
            Ok(HeadingValue::Categories(categories))
        }
    }
}

fn parse_heading_date(
    label: &str,
    missing_label: &str,
    date_context: &DateContext,
) -> Result<Option<DateValue>> {
    if label == missing_label {
        Ok(None)
    } else {
        dates::parse_markdown_at(label, date_context)
            .map(Some)
            .context("invalid date grouping")
    }
}

fn heading_list(headings: &[HeadingValue]) -> Option<&str> {
    headings.iter().find_map(|heading| match heading {
        HeadingValue::List(list) => Some(list.as_str()),
        _ => None,
    })
}

fn apply_heading_values(
    task: &mut EditedTask,
    explicit: &ExplicitFields,
    headings: &[HeadingValue],
) {
    for heading in headings {
        match heading {
            HeadingValue::List(_) | HeadingValue::Completed => {}
            HeadingValue::Priority(value) if !explicit.priority => task.priority = *value,
            HeadingValue::Due(value) if !explicit.due => task.due = value.clone(),
            HeadingValue::Start(value) if !explicit.start => task.start = value.clone(),
            HeadingValue::Categories(value) if !explicit.categories => {
                task.categories = value.clone();
            }
            _ => {}
        }
    }
}

fn split_indentation(line: &str, line_number: usize) -> Result<(usize, &str)> {
    let spaces = line.bytes().take_while(|byte| *byte == b' ').count();
    if line.as_bytes().get(spaces) == Some(&b'\t') {
        bail!("line {line_number}: task indentation must use spaces, not tabs");
    }
    if spaces % 2 != 0 {
        bail!("line {line_number}: task indentation must be a multiple of two spaces");
    }
    Ok((spaces / 2, &line[spaces..]))
}

/// Identity markers stay compact so they add little visual noise to a task
/// line. Only a trailing comment whose body is a session identity is reserved;
/// any other trailing HTML comment belongs to the summary.
const MARKER_START: &str = " <!--";
const MARKER_END: &str = "-->";

fn split_identity_marker(remainder: &str) -> Option<(&str, &str)> {
    let (summary, marker) = remainder.rsplit_once(MARKER_START)?;
    let session_id = marker.strip_suffix(MARKER_END)?;
    is_session_id(session_id).then_some((summary, session_id))
}

fn is_session_id(value: &str) -> bool {
    value.strip_prefix('t').is_some_and(|digits| {
        !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit())
    })
}

fn parse_task_line(
    line: &str,
    line_number: usize,
    manifest: &IdentityManifest,
    date_context: &DateContext,
) -> Result<(EditedTask, ExplicitFields)> {
    let (completed, remainder) = if let Some(remainder) = line.strip_prefix("- [ ] ") {
        (false, remainder)
    } else if let Some(remainder) = line.strip_prefix("- [x] ") {
        (true, remainder)
    } else {
        bail!("line {line_number}: expected a '- [ ]' or '- [x]' task");
    };

    let (summary, id) = match split_identity_marker(remainder) {
        Some((summary, session_id)) => {
            if split_identity_marker(summary).is_some() {
                bail!("line {line_number}: duplicate todomd identity marker");
            }
            let task_id = manifest
                .resolve_session_id(session_id)
                .with_context(|| format!("line {line_number}"))?;
            (summary, Some(task_id.clone()))
        }
        None => (remainder, None),
    };

    let fields =
        split_fields(summary, date_context).with_context(|| format!("line {line_number}"))?;
    let summary = parse_summary(fields.summary).with_context(|| format!("line {line_number}"))?;
    validate_summary(&summary).with_context(|| format!("line {line_number}"))?;

    let explicit = ExplicitFields {
        list: fields.list.clone(),
        priority: fields.priority.is_some(),
        categories: fields.categories.is_some(),
        start: fields.start.is_some(),
        due: fields.due.is_some(),
    };
    Ok((
        EditedTask {
            id,
            summary,
            completed,
            priority: fields.priority.unwrap_or_default(),
            categories: fields.categories.unwrap_or_default(),
            parent: None,
            start: fields.start,
            due: fields.due,
        },
        explicit,
    ))
}

struct ExplicitFields {
    list: Option<String>,
    priority: bool,
    categories: bool,
    start: bool,
    due: bool,
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
    summary.starts_with(['!', '+', '-', '@', '[', '"'])
        || summary.trim() != summary
        // A trailing identity-shaped comment would otherwise be read back as
        // this task's marker.
        || split_identity_marker(summary).is_some()
}

pub(super) fn validate_category(category: &str) -> Result<()> {
    if category.is_empty() || category.contains(['\r', '\n']) {
        bail!("task category cannot be empty or contain a newline");
    }
    Ok(())
}

fn render_list_marker(list: &str) -> String {
    if list.contains(char::is_whitespace) || list.contains('"') {
        format!("@\"{}\"", list.replace('"', "\"\""))
    } else {
        format!("@{list}")
    }
}

fn render_categories(categories: &[String]) -> Option<String> {
    (!categories.is_empty()).then(|| {
        let categories = categories.iter().collect::<BTreeSet<_>>();
        let values = categories
            .into_iter()
            .map(|category| {
                if category.contains(char::is_whitespace) || category.contains([',', '[', ']', '"'])
                {
                    format!("\"{}\"", category.replace('"', "\"\""))
                } else {
                    category.clone()
                }
            })
            .collect::<Vec<_>>()
            .join(", ");
        format!("[{values}]")
    })
}

struct ParsedFields<'a> {
    list: Option<String>,
    priority: Option<Priority>,
    categories: Option<Vec<String>>,
    start: Option<DateValue>,
    due: Option<DateValue>,
    summary: &'a str,
}

fn split_fields<'a>(
    mut remainder: &'a str,
    date_context: &DateContext,
) -> Result<ParsedFields<'a>> {
    let mut list = None;
    let mut priority = None;
    let mut categories = None;
    let mut start = None;
    let mut due = None;

    loop {
        if remainder.starts_with('!') {
            if priority.is_some() {
                bail!("task contains more than one priority marker");
            }
            let marker_len = remainder
                .chars()
                .take_while(|character| *character == '!')
                .count();
            let (marker, rest) = remainder.split_at(marker_len);
            priority = Some(
                Priority::from_marker(marker)
                    .with_context(|| format!("unknown priority marker {marker:?}"))?,
            );
            remainder = marker_remainder(rest, "priority marker")?;
            continue;
        }

        if let Some(rest) = remainder.strip_prefix('@') {
            if list.is_some() {
                bail!("task contains more than one list marker");
            }
            let (value, rest) = take_marker_value(rest, "list")?;
            list = Some(value);
            remainder = marker_remainder(rest, "list marker")?;
            continue;
        }

        if remainder.starts_with('[') {
            if categories.is_some() {
                bail!("task contains more than one category field");
            }
            let (values, rest) = take_categories(remainder)?;
            categories = Some(values);
            remainder = marker_remainder(rest, "category field")?;
            continue;
        }

        let (slot, name) = if remainder.starts_with('-') {
            (&mut due, "due")
        } else if remainder.starts_with('+') {
            (&mut start, "start")
        } else {
            break;
        };
        if slot.is_some() {
            bail!("task contains more than one {name} marker");
        }
        let (value, rest) = take_marker_value(&remainder[1..], "date")?;
        *slot = Some(
            dates::parse_markdown_at(&value, date_context)
                .with_context(|| format!("invalid {name} marker"))?,
        );
        remainder = marker_remainder(rest, &format!("{name} marker"))?;
    }

    Ok(ParsedFields {
        list,
        priority,
        categories,
        start,
        due,
        summary: remainder,
    })
}

fn take_categories(input: &str) -> Result<(Vec<String>, &str)> {
    let mut remainder = input
        .strip_prefix('[')
        .expect("category field starts with '['");
    let mut categories = BTreeSet::new();

    loop {
        remainder = remainder.trim_start_matches(' ');
        if remainder.starts_with(']') {
            bail!("category field must contain at least one category");
        }
        let (category, rest) = if remainder.starts_with('"') {
            take_marker_value(remainder, "category")?
        } else {
            let end = remainder
                .find([',', ']'])
                .context("category field must end with ']'")?;
            let raw = &remainder[..end];
            let value = raw.trim_end_matches(' ');
            if raw != value {
                bail!("an unquoted category must not have trailing whitespace");
            }
            if value.is_empty() {
                bail!("category cannot be empty");
            }
            if value.contains(char::is_whitespace) || value.contains(['[', '"']) {
                bail!("a category containing whitespace, brackets, or quotes must be quoted");
            }
            (value.to_owned(), &remainder[end..])
        };
        validate_category(&category)?;
        if !categories.insert(category.clone()) {
            bail!("duplicate category {category:?}");
        }

        remainder = rest.trim_start_matches(' ');
        if let Some(rest) = remainder.strip_prefix(']') {
            return Ok((categories.into_iter().collect(), rest));
        }
        remainder = remainder
            .strip_prefix(',')
            .context("categories must be separated by commas")?;
    }
}

fn marker_remainder<'a>(remainder: &'a str, marker: &str) -> Result<&'a str> {
    remainder
        .strip_prefix(' ')
        .with_context(|| format!("{marker} must be followed by a space and the next field"))
}

fn take_marker_value<'a>(input: &'a str, field: &str) -> Result<(String, &'a str)> {
    let Some(mut remainder) = input.strip_prefix('"') else {
        let (value, remainder) = input
            .find(' ')
            .map_or((input, ""), |index| (&input[..index], &input[index..]));
        if value.is_empty() {
            bail!("{field} marker cannot be empty");
        }
        return Ok((value.to_owned(), remainder));
    };

    let mut value = String::new();
    loop {
        let Some((character, rest)) = remainder.chars().next().map(|character| {
            let length = character.len_utf8();
            (character, &remainder[length..])
        }) else {
            bail!("quoted {field} marker must end with '\"'");
        };
        remainder = rest;
        if character != '"' {
            value.push(character);
            continue;
        }
        if let Some(rest) = remainder.strip_prefix('"') {
            value.push('"');
            remainder = rest;
            continue;
        }
        if value.is_empty() {
            bail!("{field} marker cannot be empty");
        }
        return Ok((value, remainder));
    }
}

/// Reads a summary field, honouring optional quoting.
fn parse_summary(field: &str) -> Result<String> {
    let Some(inner) = field.strip_prefix('"') else {
        if field.starts_with(['!', '+', '-', '@', '[']) {
            bail!("a summary starting with '!', '+', '-', '@', or '[' must be quoted");
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
    Ok(())
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use crate::model::{Task, TaskList};

    use super::*;

    fn test_date(value: &str) -> DateValue {
        let context = DateContext::in_timezone(
            "Etc/UTC",
            Utc.with_ymd_and_hms(2026, 9, 22, 12, 0, 0).unwrap(),
        )
        .unwrap();
        dates::parse_markdown_at(value, &context).unwrap()
    }

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
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
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
    fn list_groupings_hide_markers_and_move_roots_between_lists() {
        let state = TaskState {
            lists: vec![
                TaskList {
                    name: "Postgrad".into(),
                    tasks: vec![Task {
                        id: TaskId::new("paper"),
                        summary: "Write paper".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
                    }],
                },
                TaskList {
                    name: "Personal".into(),
                    tasks: Vec::new(),
                },
            ],
        };
        let mut manifest = IdentityManifest::default();
        let document = render(&state, &mut manifest).unwrap();
        assert!(document.contains("# Postgrad\n\n- [ ] Write paper <!--t1-->"));
        assert!(!document.contains("@Postgrad"));

        let moved = document.replace("# Postgrad", "# Personal");
        let parsed = parse(&moved, &state, &manifest).unwrap();
        assert!(parsed.lists[0].tasks.is_empty());
        assert_eq!(parsed.lists[1].tasks[0].summary, "Write paper");

        let explicit = moved.replace("- [ ] Write paper", "- [ ] @Postgrad Write paper");
        let parsed = parse(&explicit, &state, &manifest).unwrap();
        assert_eq!(parsed.lists[0].tasks[0].summary, "Write paper");
        assert!(parsed.lists[1].tasks.is_empty());
    }

    #[test]
    fn grouped_dates_hide_root_markers_but_keep_child_markers() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Work".into(),
                tasks: vec![
                    Task {
                        id: TaskId::new("root"),
                        summary: "Root".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: Some(test_date("2026-09-22")),
                    },
                    Task {
                        id: TaskId::new("child"),
                        summary: "Child".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![],
                        parent: Some(TaskId::new("root")),
                        start: None,
                        due: Some(test_date("2026-09-24")),
                    },
                ],
            }],
        };
        let view = View {
            group_by: vec![view::GroupKey::Due],
            sort_by: vec![view::SortKey::Summary],
        };
        let mut manifest = IdentityManifest::default();
        let document = render_with_view(&state, &view, &mut manifest).unwrap();
        assert!(document.contains("# 2026-09-22\n\n- [ ] Root <!--t1-->"));
        assert!(document.contains("  - [ ] -2026-09-24 Child <!--t2-->"));

        let moved = document.replace("# 2026-09-22", "# 2026-09-23");
        let parsed = parse_with_view(&moved, &state, &manifest, &view).unwrap();
        assert_eq!(parsed.lists[0].tasks[0].due, Some(test_date("2026-09-23")));
        assert_eq!(parsed.lists[0].tasks[1].due, Some(test_date("2026-09-24")));

        let explicit = moved.replace("Root <!--t1-->", "@Work -2026-09-25 Root <!--t1-->");
        let parsed = parse_with_view(&explicit, &state, &manifest, &view).unwrap();
        assert_eq!(parsed.lists[0].tasks[0].due, Some(test_date("2026-09-25")));
    }

    #[test]
    fn nested_groupings_round_trip_omitted_root_fields() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Work".into(),
                tasks: vec![Task {
                    id: TaskId::new("root"),
                    summary: "Root".into(),
                    completed: false,
                    priority: Priority::High,
                    categories: vec!["Quick Win".into()],
                    parent: None,
                    start: Some(test_date("2026-09-22 09:00")),
                    due: None,
                }],
            }],
        };
        let view = View {
            group_by: vec![
                view::GroupKey::List,
                view::GroupKey::Start,
                view::GroupKey::Priority,
                view::GroupKey::Categories,
            ],
            sort_by: vec![view::SortKey::Summary],
        };
        let mut manifest = IdentityManifest::default();

        let document = render_with_view(&state, &view, &mut manifest).unwrap();
        assert!(document.contains("#### [\"Quick Win\"]\n\n- [ ] Root <!--t1-->"));
        let parsed = parse_with_view(&document, &state, &manifest, &view).unwrap();
        let task = &parsed.lists[0].tasks[0];
        assert_eq!(task.start, Some(test_date("2026-09-22 09:00")));
        assert_eq!(task.priority, Priority::High);
        assert_eq!(task.categories, ["Quick Win"]);
    }

    #[test]
    fn rejects_unknown_grouping_headings() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };

        let error = parse(
            "# Typo\n\n- [ ] @Personal Task\n",
            &baseline,
            &IdentityManifest::default(),
        )
        .unwrap_err();

        assert!(format!("{error:#}").contains("unknown list grouping"));
    }

    #[test]
    fn completion_checkbox_takes_precedence_over_its_heading() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        let view = View {
            group_by: vec![view::GroupKey::Completed],
            sort_by: vec![view::SortKey::Summary],
        };

        let parsed = parse_with_view(
            "# Completed\n\n- [ ] @Personal Task\n",
            &baseline,
            &IdentityManifest::default(),
            &view,
        )
        .unwrap();

        assert!(!parsed.lists[0].tasks[0].completed);
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
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
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
        let input = "# Postgrad\n\n- [ ] @Postgrad Buy coffee\n\n# Personal\n\n- [x] @Personal Submit paper <!--t1-->\n";

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
            "# Personal\n\n- [ ] Ghost <!--t404-->\n",
            &baseline,
            &IdentityManifest::default(),
        )
        .unwrap_err();

        assert!(error.to_string().contains("line 3"));
    }

    #[test]
    fn only_identity_shaped_trailing_comments_are_markers() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("paper@example.test"),
                    summary: "Submit paper".into(),
                    completed: false,
                    priority: Priority::None,
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();
        let document = render(&baseline, &mut manifest).unwrap();
        assert!(
            document.contains("- [ ] Submit paper <!--t1-->"),
            "{document}"
        );

        let parsed = parse(
            "# Personal\n\n\
             - [ ] @Personal Submit paper <!--t1-->\n\
             - [ ] @Personal Ship it <!--later-->\n\
             - [ ] @Personal Note <!--t1--> in passing\n",
            &baseline,
            &manifest,
        )
        .unwrap();

        assert_eq!(
            parsed.lists[0].tasks[0].id.as_ref().map(TaskId::as_str),
            Some("paper@example.test")
        );
        assert_eq!(parsed.lists[0].tasks[1].id, None);
        assert_eq!(parsed.lists[0].tasks[1].summary, "Ship it <!--later-->");
        assert_eq!(parsed.lists[0].tasks[2].id, None);
        assert_eq!(
            parsed.lists[0].tasks[2].summary,
            "Note <!--t1--> in passing"
        );
    }

    #[test]
    fn quotes_summaries_that_end_with_an_identity_marker() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("paper@example.test"),
                    summary: "Submit paper <!--t1-->".into(),
                    completed: false,
                    priority: Priority::None,
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();

        assert!(
            document.contains("- [ ] \"Submit paper <!--t1-->\" <!--t1-->"),
            "{document}"
        );

        let parsed = parse(&document, &state, &manifest).unwrap();

        assert_eq!(
            parsed.lists[0].tasks[0].id.as_ref().map(TaskId::as_str),
            Some("paper@example.test")
        );
        assert_eq!(parsed.lists[0].tasks[0].summary, "Submit paper <!--t1-->");
    }

    #[test]
    fn rejects_duplicate_identity_markers() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("paper@example.test"),
                    summary: "Submit paper".into(),
                    completed: false,
                    priority: Priority::None,
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();
        render(&baseline, &mut manifest).unwrap();

        let error = parse(
            "# Personal\n\n- [ ] @Personal Submit paper <!--t1--> <!--t1-->\n",
            &baseline,
            &manifest,
        )
        .unwrap_err();

        assert!(
            format!("{error:#}").contains("duplicate todomd identity marker"),
            "{error:#}"
        );
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
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
                    },
                    Task {
                        id: TaskId::new("medium"),
                        summary: "Middling".into(),
                        completed: false,
                        priority: Priority::Medium,
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
                    },
                    Task {
                        id: TaskId::new("low"),
                        summary: "Whenever".into(),
                        completed: false,
                        priority: Priority::Low,
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
                    },
                    Task {
                        id: TaskId::new("none"),
                        summary: "Unset".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
                    },
                ],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();

        assert!(document.contains("- [ ] !!! Urgent <!--t1-->"));
        assert!(document.contains("- [ ] !! Middling <!--t2-->"));
        assert!(document.contains("- [ ] ! Whenever <!--t3-->"));
        assert!(document.contains("- [ ] Unset <!--t4-->"));

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
    fn renders_and_parses_category_markers() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("tagged"),
                    summary: "Email @Gabs".into(),
                    completed: false,
                    priority: Priority::Low,
                    categories: vec![
                        "say \"hi\"".into(),
                        "Blocked".into(),
                        "Quick Win".into(),
                        "Blocked".into(),
                    ],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();
        assert!(
            document.contains(
                "- [ ] ! [Blocked, \"Quick Win\", \"say \"\"hi\"\"\"] Email @Gabs <!--t1-->"
            ),
            "{document}"
        );

        let reordered = "# Personal\n\n- [ ] [\"Quick Win\", \"say \"\"hi\"\"\", Blocked] ! @Personal Email @Gabs <!--t1-->\n";
        let parsed = parse(reordered, &state, &manifest).unwrap();
        assert_eq!(
            parsed.lists[0].tasks[0].categories,
            ["Blocked", "Quick Win", "say \"hi\""]
        );
    }

    #[test]
    fn rejects_unrenderable_categories() {
        for category in ["", "line\nfeed"] {
            let state = TaskState {
                lists: vec![TaskList {
                    name: "Personal".into(),
                    tasks: vec![Task {
                        id: TaskId::new("bad-category"),
                        summary: "Task".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![category.into()],
                        parent: None,
                        start: None,
                        due: None,
                    }],
                }],
            };

            assert!(render(&state, &mut IdentityManifest::default()).is_err());
        }
    }

    #[test]
    fn quotes_summaries_that_start_like_categories() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("at-sign"),
                    summary: "@home is literal".into(),
                    completed: false,
                    priority: Priority::None,
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();
        assert!(document.contains("\"@home is literal\""), "{document}");
        assert_eq!(
            parse(&document, &state, &manifest).unwrap().lists[0].tasks[0].summary,
            "@home is literal"
        );
    }

    #[test]
    fn rejects_duplicate_category_markers() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        for document in [
            "# Personal\n\n- [ ] @Personal [Work, Work] Duplicate\n",
            "# Personal\n\n- [ ] @Personal [Work ] Trailing whitespace\n",
        ] {
            assert!(parse(document, &baseline, &IdentityManifest::default()).is_err());
        }
    }

    #[test]
    fn renders_dates_canonically_and_accepts_fields_in_any_order() {
        let context = DateContext::in_timezone(
            "America/Sao_Paulo",
            Utc.with_ymd_and_hms(2026, 9, 6, 12, 0, 0).unwrap(),
        )
        .unwrap();
        let state = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    id: TaskId::new("dated"),
                    summary: "Write grant".into(),
                    completed: false,
                    priority: Priority::Low,
                    categories: vec![],
                    parent: None,
                    start: Some(
                        dates::parse_markdown_at("2026-09-06T10:00:42-03:00", &context).unwrap(),
                    ),
                    due: Some(dates::parse_markdown_at("2026-09-07", &context).unwrap()),
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();
        assert!(
            document.contains("- [ ] -2026-09-07 +\"2026-09-06 10:00\" ! Write grant <!--t1-->"),
            "{document}"
        );

        let reordered = "# Postgrad\n\n- [ ] ! +\"2026-09-06 10:00\" @Postgrad -2026-09-07 Write grant <!--t1-->\n";
        let parsed = parse(reordered, &state, &manifest).unwrap();
        assert_eq!(parsed.lists[0].tasks[0].priority, Priority::Low);
        assert_eq!(
            parsed.lists[0].tasks[0].start.as_ref().unwrap().canonical(),
            "2026-09-06 10:00"
        );
        assert_eq!(
            parsed.lists[0].tasks[0].due.as_ref().unwrap().canonical(),
            "2026-09-07"
        );
    }

    #[test]
    fn rejects_duplicate_date_markers() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        for line in [
            "- [ ] -today -tomorrow Duplicate due",
            "- [ ] +today +tomorrow Duplicate start",
        ] {
            let document = format!("# Personal\n\n{line}\n");
            assert!(parse(&document, &baseline, &IdentityManifest::default()).is_err());
        }
    }

    #[test]
    fn round_trips_summaries_that_need_quoting() {
        let awkward = [
            "!urgent looking",
            "!!! literal marker",
            "+literal start",
            "-literal start",
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
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
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
        let mut expected = awkward.to_vec();
        expected.sort_by_key(|summary| summary.to_lowercase());
        assert_eq!(summaries, expected);
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
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();

        assert!(
            document.contains(r#"- [ ] He said "hi" to me <!--t1-->"#),
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
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();
        render(&state, &mut manifest).unwrap();

        for line in [
            "- [ ] @Postgrad !!!! Too many <!--t1-->",
            "- [ ] @Postgrad !unquoted start <!--t1-->",
            "- [ ] @Postgrad \"unterminated <!--t1-->",
            "- [ ] @Postgrad \"bad \" quoting\" <!--t1-->",
        ] {
            let document = format!("# Postgrad\n\n{line}\n");
            assert!(
                parse(&document, &state, &manifest).is_err(),
                "expected a parse error for {line:?}"
            );
        }
    }

    #[test]
    fn sole_ungrouped_list_is_implicit_for_roots() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("existing"),
                    summary: "Existing".into(),
                    completed: false,
                    priority: Priority::None,
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let view = View {
            group_by: vec![],
            sort_by: vec![view::SortKey::Summary],
        };
        let mut manifest = IdentityManifest::default();
        let mut document = render_with_view(&baseline, &view, &mut manifest).unwrap();
        assert!(document.contains("- [ ] Existing <!--t1-->"));
        assert!(!document.contains("@Personal"));

        document.push_str("- [ ] New task\n");
        let parsed = parse_with_view(&document, &baseline, &manifest, &view).unwrap();
        assert_eq!(parsed.lists[0].tasks.len(), 2);
        assert_eq!(parsed.lists[0].tasks[1].summary, "New task");
    }

    #[test]
    fn multiple_ungrouped_lists_require_root_list_markers() {
        let baseline = TaskState {
            lists: vec![
                TaskList {
                    name: "Personal".into(),
                    tasks: Vec::new(),
                },
                TaskList {
                    name: "Postgrad".into(),
                    tasks: Vec::new(),
                },
            ],
        };
        let view = View {
            group_by: vec![],
            sort_by: vec![view::SortKey::Summary],
        };

        let error = parse_with_view(
            "- [ ] Ambiguous\n",
            &baseline,
            &IdentityManifest::default(),
            &view,
        )
        .unwrap_err();
        assert!(
            format!("{error:#}").contains("when editing multiple lists"),
            "{error:#}"
        );
    }

    #[test]
    fn accepts_documents_without_headings() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };

        assert!(parse("", &baseline, &IdentityManifest::default()).is_ok());
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
                "# Personal\n\n- [ ] @Personal    \n",
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
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
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
                        categories: vec![],
                        parent: None,
                        start: None,
                        due: None,
                    },
                    Task {
                        id: child.clone(),
                        summary: "Child".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![],
                        parent: Some(root.clone()),
                        start: None,
                        due: None,
                    },
                    Task {
                        id: TaskId::new("grandchild"),
                        summary: "Grandchild".into(),
                        completed: false,
                        priority: Priority::None,
                        categories: vec![],
                        parent: Some(child.clone()),
                        start: None,
                        due: None,
                    },
                ],
            }],
        };
        let mut manifest = IdentityManifest::default();

        let document = render(&state, &mut manifest).unwrap();
        assert!(document.contains("  - [ ] Child <!--t2-->"));
        assert!(document.contains("    - [ ] Grandchild <!--t3-->"));

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
        let document =
            "# Personal\n\n- [ ] @Personal Parent\n  - [ ] Child\n    - [ ] Grandchild\n";

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
