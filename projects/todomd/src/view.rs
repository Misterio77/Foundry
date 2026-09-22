use std::{cmp::Ordering, collections::BTreeMap};

use anyhow::{Result, bail};
use clap::ValueEnum;
use serde::{Deserialize, Serialize};

use crate::model::{Priority, Task, TaskId, TaskState};

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
#[value(rename_all = "lower")]
pub enum GroupKey {
    List,
    Completed,
    Priority,
    Due,
    Start,
    Categories,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize, ValueEnum)]
#[serde(rename_all = "lowercase")]
#[value(rename_all = "lower")]
pub enum SortKey {
    List,
    Completed,
    Manual,
    Due,
    Start,
    Priority,
    Summary,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct View {
    pub group_by: Vec<GroupKey>,
    pub sort_by: Vec<SortKey>,
}

impl Default for View {
    fn default() -> Self {
        Self {
            group_by: vec![GroupKey::List],
            sort_by: vec![SortKey::Completed, SortKey::Priority, SortKey::Summary],
        }
    }
}

impl View {
    pub fn validate(&self, name: &str) -> Result<()> {
        validate_unique(&format!("{name}.group_by"), &self.group_by, true)?;
        validate_unique(&format!("{name}.sort_by"), &self.sort_by, false)
    }
}

fn validate_unique<T: Ord>(name: &str, keys: &[T], empty_allowed: bool) -> Result<()> {
    if !empty_allowed && keys.is_empty() {
        bail!("{name} must contain at least one key");
    }
    if keys.windows(2).count() > 0 {
        let mut sorted = keys.iter().collect::<Vec<_>>();
        sorted.sort_unstable();
        if sorted.windows(2).any(|pair| pair[0] == pair[1]) {
            bail!("{name} must not contain duplicate keys");
        }
    }
    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum GroupValue {
    List(usize, String),
    Completed(bool),
    Priority(Priority),
    Due(Option<String>),
    Start(Option<String>),
    Categories(Vec<String>),
}

impl GroupValue {
    fn label(&self) -> String {
        match self {
            Self::List(_, name) => name.clone(),
            Self::Completed(false) => "Incomplete".into(),
            Self::Completed(true) => "Completed".into(),
            Self::Priority(Priority::High) => "High priority".into(),
            Self::Priority(Priority::Medium) => "Medium priority".into(),
            Self::Priority(Priority::Low) => "Low priority".into(),
            Self::Priority(Priority::None) => "No priority".into(),
            Self::Due(Some(value)) => value.clone(),
            Self::Due(None) => "No due date".into(),
            Self::Start(Some(value)) => value.clone(),
            Self::Start(None) => "No start date".into(),
            Self::Categories(categories) if categories.is_empty() => "No categories".into(),
            Self::Categories(categories) => format!("[{}]", categories.join(", ")),
        }
    }
}

#[derive(Clone, Debug)]
pub struct ProjectedTask<'a> {
    pub task: &'a Task,
    pub depth: usize,
}

#[derive(Clone, Debug)]
pub struct ProjectedTree<'a> {
    pub headings: Vec<String>,
    pub list_name: &'a str,
    pub tasks: Vec<ProjectedTask<'a>>,
}

pub fn project<'a>(state: &'a TaskState, view: &View) -> Vec<ProjectedTree<'a>> {
    let list_order = state
        .lists
        .iter()
        .enumerate()
        .map(|(index, list)| (list.name.as_str(), index))
        .collect::<BTreeMap<_, _>>();
    let source_order = state
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .enumerate()
        .map(|(index, task)| (task.id.clone(), index))
        .collect::<BTreeMap<_, _>>();
    let task_list_order = state
        .lists
        .iter()
        .enumerate()
        .flat_map(|(index, list)| list.tasks.iter().map(move |task| (task.id.clone(), index)))
        .collect::<BTreeMap<_, _>>();
    let mut trees = Vec::new();

    for list in &state.lists {
        let mut children: BTreeMap<Option<TaskId>, Vec<&Task>> = BTreeMap::new();
        for task in &list.tasks {
            children.entry(task.parent.clone()).or_default().push(task);
        }
        for siblings in children.values_mut() {
            siblings.sort_by(|left, right| {
                task_order(left, right, &view.sort_by, &source_order, &task_list_order)
            });
        }
        for &root in children.get(&None).into_iter().flatten() {
            let group = view
                .group_by
                .iter()
                .map(|key| group_value(*key, root, &list.name, &list_order))
                .collect::<Vec<_>>();
            let mut tasks = Vec::new();
            append_tree(root, 0, &children, &mut tasks);
            trees.push((group, root, list.name.as_str(), tasks));
        }
    }

    trees.sort_by(|(left_group, left, _, _), (right_group, right, _, _)| {
        group_order(left_group, right_group, &view.group_by)
            .then_with(|| task_order(left, right, &view.sort_by, &source_order, &task_list_order))
    });
    trees
        .into_iter()
        .map(|(group, _, list_name, tasks)| ProjectedTree {
            headings: group.into_iter().map(|value| value.label()).collect(),
            list_name,
            tasks,
        })
        .collect()
}

fn append_tree<'a>(
    task: &'a Task,
    depth: usize,
    children: &BTreeMap<Option<TaskId>, Vec<&'a Task>>,
    output: &mut Vec<ProjectedTask<'a>>,
) {
    output.push(ProjectedTask { task, depth });
    for &child in children.get(&Some(task.id.clone())).into_iter().flatten() {
        append_tree(child, depth + 1, children, output);
    }
}

fn group_value(
    key: GroupKey,
    task: &Task,
    list_name: &str,
    list_order: &BTreeMap<&str, usize>,
) -> GroupValue {
    match key {
        GroupKey::List => GroupValue::List(list_order[list_name], list_name.to_owned()),
        GroupKey::Completed => GroupValue::Completed(task.completed),
        GroupKey::Priority => GroupValue::Priority(task.priority),
        GroupKey::Due => GroupValue::Due(task.due.as_ref().map(|value| value.canonical())),
        GroupKey::Start => GroupValue::Start(task.start.as_ref().map(|value| value.canonical())),
        GroupKey::Categories => GroupValue::Categories(task.categories.clone()),
    }
}

fn group_order(left: &[GroupValue], right: &[GroupValue], keys: &[GroupKey]) -> Ordering {
    for ((left, right), key) in left.iter().zip(right).zip(keys) {
        let ordering = match (key, left, right) {
            (GroupKey::List, GroupValue::List(left, _), GroupValue::List(right, _)) => {
                left.cmp(right)
            }
            (GroupKey::Completed, GroupValue::Completed(left), GroupValue::Completed(right)) => {
                left.cmp(right)
            }
            (GroupKey::Priority, GroupValue::Priority(left), GroupValue::Priority(right)) => {
                right.cmp(left)
            }
            (GroupKey::Due, GroupValue::Due(left), GroupValue::Due(right))
            | (GroupKey::Start, GroupValue::Start(left), GroupValue::Start(right)) => {
                compare_optional(left.as_ref(), right.as_ref())
            }
            (GroupKey::Categories, GroupValue::Categories(left), GroupValue::Categories(right)) => {
                compare_optional(
                    (!left.is_empty()).then_some(left),
                    (!right.is_empty()).then_some(right),
                )
            }
            _ => unreachable!("group value matches its key"),
        };
        if ordering != Ordering::Equal {
            return ordering;
        }
    }
    Ordering::Equal
}

fn task_order(
    left: &Task,
    right: &Task,
    sort_keys: &[SortKey],
    source_order: &BTreeMap<TaskId, usize>,
    task_list_order: &BTreeMap<TaskId, usize>,
) -> Ordering {
    for key in sort_keys {
        let ordering = match key {
            SortKey::List => task_list_order[&left.id].cmp(&task_list_order[&right.id]),
            SortKey::Completed => left.completed.cmp(&right.completed),
            SortKey::Manual => source_order[&left.id].cmp(&source_order[&right.id]),
            SortKey::Due => compare_optional(
                left.due.as_ref().map(|value| value.canonical()),
                right.due.as_ref().map(|value| value.canonical()),
            ),
            SortKey::Start => compare_optional(
                left.start.as_ref().map(|value| value.canonical()),
                right.start.as_ref().map(|value| value.canonical()),
            ),
            SortKey::Priority => right.priority.cmp(&left.priority),
            SortKey::Summary => left
                .summary
                .to_lowercase()
                .cmp(&right.summary.to_lowercase()),
        };
        if ordering != Ordering::Equal {
            return ordering;
        }
    }
    left.id.cmp(&right.id)
}

fn compare_optional<T: Ord>(left: Option<T>, right: Option<T>) -> Ordering {
    match (left, right) {
        (Some(left), Some(right)) => left.cmp(&right),
        (Some(_), None) => Ordering::Less,
        (None, Some(_)) => Ordering::Greater,
        (None, None) => Ordering::Equal,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{TaskList, TaskState};

    fn task(id: &str, summary: &str, parent: Option<&str>) -> Task {
        Task {
            id: TaskId::new(id),
            summary: summary.into(),
            completed: false,
            priority: Priority::None,
            categories: Vec::new(),
            parent: parent.map(TaskId::new),
            start: None,
            due: None,
        }
    }

    #[test]
    fn groups_root_trees_and_sorts_descendants() {
        let state = TaskState {
            lists: vec![TaskList {
                name: "Work".into(),
                tasks: vec![
                    task("root-b", "Beta", None),
                    task("child-b", "Zulu", Some("root-b")),
                    task("child-a", "Alpha", Some("root-b")),
                    task("root-a", "Alpha", None),
                ],
            }],
        };

        let projected = project(&state, &View::default());

        assert_eq!(projected.len(), 2);
        assert_eq!(projected[0].tasks[0].task.id.as_str(), "root-a");
        assert_eq!(projected[1].tasks[0].task.id.as_str(), "root-b");
        assert_eq!(projected[1].tasks[1].task.id.as_str(), "child-a");
        assert_eq!(projected[1].tasks[2].task.id.as_str(), "child-b");
        assert_eq!(projected[1].tasks[1].depth, 1);
    }

    #[test]
    fn sorts_roots_by_selected_list_order() {
        let state = TaskState {
            lists: vec![
                TaskList {
                    name: "Personal".into(),
                    tasks: vec![task("personal", "Zulu", None)],
                },
                TaskList {
                    name: "Work".into(),
                    tasks: vec![task("work", "Alpha", None)],
                },
            ],
        };
        let view = View {
            group_by: Vec::new(),
            sort_by: vec![SortKey::Priority, SortKey::List, SortKey::Summary],
        };

        let projected = project(&state, &view);

        assert_eq!(projected[0].list_name, "Personal");
        assert_eq!(projected[1].list_name, "Work");
    }

    #[test]
    fn category_sets_are_single_group_values() {
        let mut categorized = task("a", "Alpha", None);
        categorized.categories = vec!["Home".into(), "Urgent".into()];
        let state = TaskState {
            lists: vec![TaskList {
                name: "Work".into(),
                tasks: vec![categorized],
            }],
        };
        let view = View {
            group_by: vec![GroupKey::Categories],
            sort_by: vec![SortKey::Summary],
        };

        assert_eq!(project(&state, &view)[0].headings, ["[Home, Urgent]"]);
    }
}
