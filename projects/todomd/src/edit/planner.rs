use std::{collections::BTreeMap, fmt};

use anyhow::{Context, Result, bail};
use serde::Serialize;

use super::markdown::render_category_marker;
use crate::{
    dates::{self, DateValue},
    model::{EditedTaskState, Priority, TaskId, TaskReference, TaskState},
};

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub enum Operation {
    Rename {
        id: TaskId,
        list: String,
        from: String,
        to: String,
    },
    Complete {
        id: TaskId,
        list: String,
        summary: String,
    },
    Reopen {
        id: TaskId,
        list: String,
        summary: String,
    },
    Reprioritize {
        id: TaskId,
        list: String,
        summary: String,
        from: Priority,
        to: Priority,
    },
    Recategorize {
        id: TaskId,
        list: String,
        summary: String,
        from: Vec<String>,
        to: Vec<String>,
    },
    Reschedule {
        id: TaskId,
        list: String,
        summary: String,
        from_start: Option<DateValue>,
        to_start: Option<DateValue>,
        from_due: Option<DateValue>,
        to_due: Option<DateValue>,
    },
    Reparent {
        id: TaskId,
        list: String,
        summary: String,
        from: Option<TaskReference>,
        to: Option<TaskReference>,
        from_summary: Option<String>,
        to_summary: Option<String>,
    },
    Create {
        draft_id: usize,
        list: String,
        summary: String,
        priority: Priority,
        categories: Vec<String>,
        start: Option<DateValue>,
        due: Option<DateValue>,
        parent: Option<TaskReference>,
        parent_summary: Option<String>,
    },
    Move {
        id: TaskId,
        summary: String,
        from: String,
        to: String,
    },
    Delete {
        id: TaskId,
        list: String,
        summary: String,
    },
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ChangePlan {
    pub operations: Vec<Operation>,
    list_order: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Reconciliation {
    NoChange,
    Outgoing(ChangePlan),
    Inbound,
    Conflict,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ComparableTask {
    list: String,
    summary: String,
    completed: bool,
    priority: Priority,
    categories: Vec<String>,
    parent: Option<TaskReference>,
    start: Option<DateValue>,
    due: Option<DateValue>,
}

type IdentifiedTasks = BTreeMap<TaskId, ComparableTask>;
type DraftTasks = Vec<(usize, ComparableTask)>;

pub fn reconcile(
    baseline: &TaskState,
    markdown: &EditedTaskState,
    current_ics: &TaskState,
) -> Result<Reconciliation> {
    let baseline_tasks = task_map(baseline);
    let current_tasks = task_map(current_ics);
    let (mut markdown_tasks, mut new_tasks) = edited_task_map(markdown)?;
    prepare_dates(&baseline_tasks, &mut markdown_tasks, &mut new_tasks)?;

    for task_id in markdown_tasks.keys() {
        if !baseline_tasks.contains_key(task_id) {
            bail!(
                "Markdown contains task identity {:?} outside the baseline",
                task_id.as_str()
            );
        }
    }
    for (_, task) in &new_tasks {
        if task.completed {
            bail!("new task {:?} cannot already be completed", task.summary);
        }
    }

    let markdown_changed = markdown_tasks != baseline_tasks || !new_tasks.is_empty();
    let ics_changed = current_tasks != baseline_tasks;

    match (markdown_changed, ics_changed) {
        (false, false) => Ok(Reconciliation::NoChange),
        (false, true) => Ok(Reconciliation::Inbound),
        (true, true) => Ok(Reconciliation::Conflict),
        (true, false) => Ok(Reconciliation::Outgoing(build_plan(
            baseline,
            &baseline_tasks,
            &markdown_tasks,
            &new_tasks,
        ))),
    }
}

fn build_plan(
    baseline: &TaskState,
    baseline_tasks: &IdentifiedTasks,
    markdown_tasks: &IdentifiedTasks,
    new_tasks: &DraftTasks,
) -> ChangePlan {
    let mut operations = Vec::new();
    for (id, original) in baseline_tasks {
        let Some(edited) = markdown_tasks.get(id) else {
            operations.push(Operation::Delete {
                id: id.clone(),
                list: original.list.clone(),
                summary: original.summary.clone(),
            });
            continue;
        };

        if original.list != edited.list {
            operations.push(Operation::Move {
                id: id.clone(),
                summary: edited.summary.clone(),
                from: original.list.clone(),
                to: edited.list.clone(),
            });
        }
        if original.summary != edited.summary {
            operations.push(Operation::Rename {
                id: id.clone(),
                list: edited.list.clone(),
                from: original.summary.clone(),
                to: edited.summary.clone(),
            });
        }
        if original.priority != edited.priority {
            operations.push(Operation::Reprioritize {
                id: id.clone(),
                list: edited.list.clone(),
                summary: edited.summary.clone(),
                from: original.priority,
                to: edited.priority,
            });
        }
        if original.categories != edited.categories {
            operations.push(Operation::Recategorize {
                id: id.clone(),
                list: edited.list.clone(),
                summary: edited.summary.clone(),
                from: original.categories.clone(),
                to: edited.categories.clone(),
            });
        }
        if original.start != edited.start || original.due != edited.due {
            operations.push(Operation::Reschedule {
                id: id.clone(),
                list: edited.list.clone(),
                summary: edited.summary.clone(),
                from_start: original.start.clone(),
                to_start: edited.start.clone(),
                from_due: original.due.clone(),
                to_due: edited.due.clone(),
            });
        }
        if original.parent != edited.parent {
            operations.push(Operation::Reparent {
                id: id.clone(),
                list: edited.list.clone(),
                summary: edited.summary.clone(),
                from: original.parent.clone(),
                to: edited.parent.clone(),
                from_summary: parent_summary(original.parent.as_ref(), baseline_tasks, new_tasks),
                to_summary: parent_summary(edited.parent.as_ref(), markdown_tasks, new_tasks),
            });
        }
        match (original.completed, edited.completed) {
            (false, true) => operations.push(Operation::Complete {
                id: id.clone(),
                list: edited.list.clone(),
                summary: edited.summary.clone(),
            }),
            (true, false) => operations.push(Operation::Reopen {
                id: id.clone(),
                list: edited.list.clone(),
                summary: edited.summary.clone(),
            }),
            _ => {}
        }
    }

    for (draft_id, task) in new_tasks {
        operations.push(Operation::Create {
            draft_id: *draft_id,
            list: task.list.clone(),
            summary: task.summary.clone(),
            priority: task.priority,
            categories: task.categories.clone(),
            start: task.start.clone(),
            due: task.due.clone(),
            parent: task.parent.clone(),
            parent_summary: parent_summary(task.parent.as_ref(), markdown_tasks, new_tasks),
        });
    }

    let list_positions = baseline
        .lists
        .iter()
        .enumerate()
        .map(|(index, list)| (list.name.as_str(), index))
        .collect::<BTreeMap<_, _>>();
    operations.sort_by(|left, right| {
        operation_sort_key(left, &list_positions).cmp(&operation_sort_key(right, &list_positions))
    });

    ChangePlan {
        operations,
        list_order: baseline
            .lists
            .iter()
            .map(|list| list.name.clone())
            .collect(),
    }
}

fn task_map(state: &TaskState) -> IdentifiedTasks {
    state
        .lists
        .iter()
        .flat_map(|list| {
            list.tasks.iter().map(|task| {
                (
                    task.id.clone(),
                    ComparableTask {
                        list: list.name.clone(),
                        summary: task.summary.clone(),
                        completed: task.completed,
                        priority: task.priority,
                        categories: task.categories.clone(),
                        parent: task.parent.clone().map(TaskReference::Existing),
                        start: task.start.clone(),
                        due: task.due.clone(),
                    },
                )
            })
        })
        .collect()
}

fn edited_task_map(state: &EditedTaskState) -> Result<(IdentifiedTasks, DraftTasks)> {
    let mut identified = BTreeMap::new();
    let mut new = Vec::new();
    let mut next_draft_id = 1;

    for list in &state.lists {
        for task in &list.tasks {
            let comparable = ComparableTask {
                list: list.name.clone(),
                summary: task.summary.clone(),
                completed: task.completed,
                priority: task.priority,
                categories: task.categories.clone(),
                parent: task.parent.clone(),
                start: task.start.clone(),
                due: task.due.clone(),
            };
            match &task.id {
                Some(id) => {
                    if identified.insert(id.clone(), comparable).is_some() {
                        bail!(
                            "Markdown contains duplicate task identity {:?}",
                            id.as_str()
                        );
                    }
                }
                None => {
                    new.push((next_draft_id, comparable));
                    next_draft_id += 1;
                }
            }
        }
    }

    validate_edited_hierarchy(&identified, &new)?;
    Ok((identified, new))
}

fn prepare_dates(
    baseline: &IdentifiedTasks,
    markdown: &mut IdentifiedTasks,
    new_tasks: &mut DraftTasks,
) -> Result<()> {
    for (id, task) in markdown {
        let Some(original) = baseline.get(id) else {
            continue;
        };
        if task.start != original.start || task.due != original.due {
            dates::normalize_and_validate(&mut task.start, &mut task.due)
                .with_context(|| format!("invalid dates for task {:?}", task.summary))?;
        }
    }
    for (_, task) in new_tasks {
        dates::normalize_and_validate(&mut task.start, &mut task.due)
            .with_context(|| format!("invalid dates for new task {:?}", task.summary))?;
    }
    Ok(())
}

fn parent_summary(
    parent: Option<&TaskReference>,
    identified: &IdentifiedTasks,
    new_tasks: &DraftTasks,
) -> Option<String> {
    match parent? {
        TaskReference::Existing(id) => identified.get(id).map(|task| task.summary.clone()),
        TaskReference::Draft(draft_id) => new_tasks
            .iter()
            .find(|(candidate, _)| candidate == draft_id)
            .map(|(_, task)| task.summary.clone()),
    }
}

fn validate_edited_hierarchy(identified: &IdentifiedTasks, new_tasks: &DraftTasks) -> Result<()> {
    let mut tasks = BTreeMap::new();
    for (id, task) in identified {
        tasks.insert(TaskReference::Existing(id.clone()), task);
    }
    for (draft_id, task) in new_tasks {
        tasks.insert(TaskReference::Draft(*draft_id), task);
    }

    for (reference, task) in &tasks {
        let Some(parent) = &task.parent else {
            continue;
        };
        let parent_task = tasks.get(parent).ok_or_else(|| {
            anyhow::anyhow!("task {reference:?} names a parent absent from Markdown")
        })?;
        if task.list != parent_task.list {
            bail!("a task and its parent must remain in the same list");
        }
    }

    for start in tasks.keys() {
        let mut seen = BTreeMap::new();
        let mut path = Vec::new();
        let mut current = Some(start);
        while let Some(reference) = current {
            if let Some(index) = seen.insert(reference, path.len()) {
                let cycle = path[index..]
                    .iter()
                    .chain(std::iter::once(&reference))
                    .map(|item| format!("{item:?}"))
                    .collect::<Vec<_>>()
                    .join(" -> ");
                bail!("Markdown task hierarchy contains a cycle: {cycle}");
            }
            path.push(reference);
            current = tasks.get(reference).and_then(|task| task.parent.as_ref());
        }
    }
    Ok(())
}

fn display_date(value: &Option<DateValue>) -> String {
    value
        .as_ref()
        .map_or_else(|| "none".to_owned(), DateValue::canonical)
}

fn operation_sort_key<'a>(
    operation: &'a Operation,
    list_positions: &BTreeMap<&str, usize>,
) -> (usize, u8, &'a str) {
    let (list, kind, summary) = match operation {
        Operation::Rename { list, to, .. } => (list.as_str(), 0, to.as_str()),
        Operation::Complete { list, summary, .. } => (list.as_str(), 1, summary.as_str()),
        Operation::Reopen { list, summary, .. } => (list.as_str(), 2, summary.as_str()),
        Operation::Reprioritize { list, summary, .. } => (list.as_str(), 3, summary.as_str()),
        Operation::Recategorize { list, summary, .. } => (list.as_str(), 4, summary.as_str()),
        Operation::Reschedule { list, summary, .. } => (list.as_str(), 5, summary.as_str()),
        Operation::Reparent { list, summary, .. } => (list.as_str(), 6, summary.as_str()),
        Operation::Create { list, summary, .. } => (list.as_str(), 7, summary.as_str()),
        Operation::Move { to, summary, .. } => (to.as_str(), 8, summary.as_str()),
        Operation::Delete { list, summary, .. } => (list.as_str(), 9, summary.as_str()),
    };
    (
        *list_positions.get(list).unwrap_or(&usize::MAX),
        kind,
        summary,
    )
}

impl Operation {
    fn list(&self) -> &str {
        match self {
            Self::Rename { list, .. }
            | Self::Complete { list, .. }
            | Self::Reopen { list, .. }
            | Self::Reprioritize { list, .. }
            | Self::Recategorize { list, .. }
            | Self::Reschedule { list, .. }
            | Self::Reparent { list, .. }
            | Self::Create { list, .. }
            | Self::Delete { list, .. } => list,
            Self::Move { to, .. } => to,
        }
    }
}

impl fmt::Display for ChangePlan {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (index, list) in self
            .list_order
            .iter()
            .filter(|list| {
                self.operations
                    .iter()
                    .any(|operation| operation.list() == *list)
            })
            .enumerate()
        {
            if index > 0 {
                writeln!(formatter)?;
            }
            writeln!(formatter, "{list}:")?;
            for operation in self
                .operations
                .iter()
                .filter(|operation| operation.list() == list)
            {
                match operation {
                    Operation::Rename { from, to, .. } => {
                        writeln!(formatter, "  renamed   {from:?} -> {to:?}")?;
                    }
                    Operation::Complete { summary, .. } => {
                        writeln!(formatter, "  completed {summary}")?;
                    }
                    Operation::Reopen { summary, .. } => {
                        writeln!(formatter, "  reopened  {summary}")?;
                    }
                    Operation::Reprioritize {
                        summary, from, to, ..
                    } => {
                        writeln!(
                            formatter,
                            "  priority  {summary} ({} -> {})",
                            from.label(),
                            to.label()
                        )?;
                    }
                    Operation::Recategorize {
                        summary, from, to, ..
                    } => {
                        let display = |categories: &[String]| {
                            if categories.is_empty() {
                                "none".to_owned()
                            } else {
                                categories
                                    .iter()
                                    .map(|category| render_category_marker(category))
                                    .collect::<Vec<_>>()
                                    .join(" ")
                            }
                        };
                        writeln!(
                            formatter,
                            "  categories {summary} ({} -> {})",
                            display(from),
                            display(to)
                        )?;
                    }
                    Operation::Reschedule {
                        summary,
                        from_start,
                        to_start,
                        from_due,
                        to_due,
                        ..
                    } => {
                        writeln!(
                            formatter,
                            "  dates     {summary} (start: {} -> {}; due: {} -> {})",
                            display_date(from_start),
                            display_date(to_start),
                            display_date(from_due),
                            display_date(to_due)
                        )?;
                    }
                    Operation::Reparent {
                        summary,
                        from_summary,
                        to_summary,
                        ..
                    } => match (from_summary, to_summary) {
                        (None, Some(parent)) => {
                            writeln!(formatter, "  nested    {summary} under {parent}")?;
                        }
                        (Some(parent), None) => {
                            writeln!(formatter, "  detached  {summary} from {parent}")?;
                        }
                        (Some(from), Some(to)) => {
                            writeln!(formatter, "  reparented {summary} ({from} -> {to})")?;
                        }
                        (None, None) => writeln!(formatter, "  reparented {summary}")?,
                    },
                    Operation::Create {
                        summary,
                        priority,
                        categories,
                        start,
                        due,
                        parent_summary,
                        ..
                    } => {
                        let mut fields = Vec::new();
                        if let Some(due) = due {
                            fields.push(format!("-{}", due.canonical()));
                        }
                        if let Some(start) = start {
                            fields.push(format!("+{}", start.canonical()));
                        }
                        if priority != &Priority::None {
                            fields.push(priority.label().to_owned());
                        }
                        fields.extend(
                            categories
                                .iter()
                                .map(|category| render_category_marker(category)),
                        );
                        let fields = if fields.is_empty() {
                            String::new()
                        } else {
                            format!(" ({})", fields.join(" "))
                        };
                        let parent = parent_summary
                            .as_ref()
                            .map_or_else(String::new, |parent| format!(" under {parent}"));
                        writeln!(formatter, "  created   {summary}{fields}{parent}")?;
                    }
                    Operation::Move { summary, from, .. } => {
                        writeln!(formatter, "  moved     {summary} <- {from}")?;
                    }
                    Operation::Delete { summary, .. } => {
                        writeln!(formatter, "  deleted   {summary}")?;
                    }
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use crate::{
        dates::{DateContext, parse_markdown_at},
        model::{EditedTask, EditedTaskList, Task, TaskList},
    };

    use super::*;

    fn date(value: &str) -> DateValue {
        let context = DateContext::in_timezone(
            "America/Sao_Paulo",
            Utc.with_ymd_and_hms(2026, 9, 6, 12, 0, 0).unwrap(),
        )
        .unwrap();
        parse_markdown_at(value, &context).unwrap()
    }

    fn task(id: &str, summary: &str) -> Task {
        Task {
            id: TaskId::new(id),
            summary: summary.into(),
            completed: false,
            priority: Priority::None,
            categories: vec![],
            parent: None,
            start: None,
            due: None,
        }
    }

    fn completed_task(id: &str, summary: &str) -> Task {
        Task {
            completed: true,
            ..task(id, summary)
        }
    }

    fn edited(id: Option<&str>, summary: &str, completed: bool) -> EditedTask {
        EditedTask {
            id: id.map(TaskId::new),
            summary: summary.into(),
            completed,
            priority: Priority::None,
            categories: vec![],
            parent: None,
            start: None,
            due: None,
        }
    }

    #[test]
    fn a_new_task_carries_its_priority_marker() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: Vec::new(),
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    priority: Priority::High,
                    ..edited(None, "Foo", false)
                }],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert_eq!(
            plan.operations,
            vec![Operation::Create {
                draft_id: 1,
                list: "Postgrad".into(),
                summary: "Foo".into(),
                priority: Priority::High,
                categories: vec![],
                start: None,
                due: None,
                parent: None,
                parent_summary: None,
            }]
        );
        assert!(format!("{plan}").contains("created   Foo (!!!)"));
    }

    #[test]
    fn changing_a_priority_marker_plans_a_reprioritize() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    priority: Priority::High,
                    ..task("paper", "Write paper")
                }],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    priority: Priority::Low,
                    ..edited(Some("paper"), "Write paper", false)
                }],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert_eq!(
            plan.operations,
            vec![Operation::Reprioritize {
                id: TaskId::new("paper"),
                list: "Postgrad".into(),
                summary: "Write paper".into(),
                from: Priority::High,
                to: Priority::Low,
            }]
        );
        assert!(format!("{plan}").contains("priority  Write paper (!!! -> !)"));
    }

    #[test]
    fn changing_categories_plans_a_recategorize() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    categories: vec!["Old".into()],
                    ..task("paper", "Write paper")
                }],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    categories: vec!["New".into(), "Quick Win".into()],
                    ..edited(Some("paper"), "Write paper", false)
                }],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert_eq!(
            plan.operations,
            vec![Operation::Recategorize {
                id: TaskId::new("paper"),
                list: "Postgrad".into(),
                summary: "Write paper".into(),
                from: vec!["Old".into()],
                to: vec!["New".into(), "Quick Win".into()],
            }]
        );
        assert!(format!("{plan}").contains("categories Write paper (@Old -> @New @\"Quick Win\")"));
    }

    #[test]
    fn an_unchanged_priority_level_is_not_a_change() {
        // A task stored as PRIORITY:4 reads as !!!; leaving the marker alone
        // must not plan anything, so the stored value survives.
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    priority: Priority::High,
                    ..task("paper", "Write paper")
                }],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    priority: Priority::High,
                    ..edited(Some("paper"), "Write paper", false)
                }],
            }],
        };

        assert_eq!(
            reconcile(&baseline, &markdown, &baseline).unwrap(),
            Reconciliation::NoChange
        );
    }

    #[test]
    fn unchanged_rendered_minute_preserves_source_seconds() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    due: Some(date("2026-09-07T20:00:42-03:00")),
                    ..task("paper", "Write paper")
                }],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    due: Some(date("2026-09-07 20:00")),
                    ..edited(Some("paper"), "Write paper", false)
                }],
            }],
        };

        assert_eq!(
            reconcile(&baseline, &markdown, &baseline).unwrap(),
            Reconciliation::NoChange
        );
    }

    #[test]
    fn changing_a_mixed_date_pair_promotes_the_date_side() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    start: Some(date("2026-09-07")),
                    due: Some(date("2026-09-08")),
                    ..task("paper", "Write paper")
                }],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    start: Some(date("2026-09-07")),
                    due: Some(date("2026-09-08 20:00:42")),
                    ..edited(Some("paper"), "Write paper", false)
                }],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };
        let operation = plan
            .operations
            .iter()
            .find(|operation| matches!(operation, Operation::Reschedule { .. }))
            .unwrap();
        assert!(matches!(
            operation,
            Operation::Reschedule {
                to_start: Some(DateValue::DateTime(_)),
                to_due: Some(DateValue::DateTime(_)),
                ..
            }
        ));
        assert!(format!("{plan}").contains("dates     Write paper"));
    }

    #[test]
    fn preserves_an_untouched_inverted_source_pair() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![Task {
                    start: Some(date("2026-09-08")),
                    due: Some(date("2026-09-07")),
                    ..task("paper", "Write paper")
                }],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    start: Some(date("2026-09-08")),
                    due: Some(date("2026-09-07")),
                    ..edited(Some("paper"), "Rename only", false)
                }],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };
        assert_eq!(plan.operations.len(), 1);
        assert!(matches!(plan.operations[0], Operation::Rename { .. }));
    }

    #[test]
    fn rejects_due_before_start_after_a_date_edit() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![task("paper", "Write paper")],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![EditedTask {
                    start: Some(date("2026-09-08")),
                    due: Some(date("2026-09-07")),
                    ..edited(Some("paper"), "Write paper", false)
                }],
            }],
        };

        let error = reconcile(&baseline, &markdown, &baseline).unwrap_err();
        assert!(error.to_string().contains("invalid dates"));
        assert!(format!("{error:#}").contains("must not be earlier"));
    }

    #[test]
    fn unchecking_a_completed_task_plans_a_reopen() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![completed_task("read", "Read chapter four")],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![edited(Some("read"), "Read chapter four", false)],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert_eq!(
            plan.operations,
            vec![Operation::Reopen {
                id: TaskId::new("read"),
                list: "Postgrad".into(),
                summary: "Read chapter four".into(),
            }]
        );
        assert!(format!("{plan}").contains("reopened  Read chapter four"));
    }

    #[test]
    fn leaving_a_completed_task_checked_is_not_a_change() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Postgrad".into(),
                tasks: vec![completed_task("read", "Read chapter four")],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Postgrad".into(),
                tasks: vec![edited(Some("read"), "Read chapter four", true)],
            }],
        };

        assert_eq!(
            reconcile(&baseline, &markdown, &baseline).unwrap(),
            Reconciliation::NoChange
        );
    }

    #[test]
    fn ignores_task_reordering() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![task("a", "A"), task("b", "B")],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![edited(Some("b"), "B", false), edited(Some("a"), "A", false)],
            }],
        };

        assert_eq!(
            reconcile(&baseline, &markdown, &baseline).unwrap(),
            Reconciliation::NoChange
        );
    }

    #[test]
    fn plans_all_mvp_operations() {
        let baseline = TaskState {
            lists: vec![
                TaskList {
                    name: "Postgrad".into(),
                    tasks: vec![task("paper", "Write paper"), task("old", "Old task")],
                },
                TaskList {
                    name: "Personal".into(),
                    tasks: Vec::new(),
                },
            ],
        };
        let markdown = EditedTaskState {
            lists: vec![
                EditedTaskList {
                    name: "Postgrad".into(),
                    tasks: vec![edited(None, "Buy coffee", false)],
                },
                EditedTaskList {
                    name: "Personal".into(),
                    tasks: vec![edited(Some("paper"), "Submit paper", true)],
                },
            ],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert_eq!(plan.operations.len(), 5);
        assert!(plan.operations.iter().any(
            |operation| matches!(operation, Operation::Move { id, .. } if id.as_str() == "paper")
        ));
        assert!(plan.operations.iter().any(
            |operation| matches!(operation, Operation::Rename { id, .. } if id.as_str() == "paper")
        ));
        assert!(plan.operations.iter().any(|operation| matches!(operation, Operation::Complete { id, .. } if id.as_str() == "paper")));
        assert!(plan.operations.iter().any(
            |operation| matches!(operation, Operation::Delete { id, .. } if id.as_str() == "old")
        ));
        assert!(plan.operations.iter().any(|operation| matches!(operation, Operation::Create { summary, .. } if summary == "Buy coffee")));
    }

    #[test]
    fn distinguishes_inbound_changes_and_conflicts() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![task("a", "A")],
            }],
        };
        let unchanged_markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![edited(Some("a"), "A", false)],
            }],
        };
        let changed_markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![edited(Some("a"), "Markdown", false)],
            }],
        };
        let current_ics = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![task("a", "ICS")],
            }],
        };

        assert_eq!(
            reconcile(&baseline, &unchanged_markdown, &current_ics).unwrap(),
            Reconciliation::Inbound
        );
        assert_eq!(
            reconcile(&baseline, &changed_markdown, &current_ics).unwrap(),
            Reconciliation::Conflict
        );
    }

    #[test]
    fn gives_identical_new_tasks_distinct_draft_ids() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![
                    edited(None, "Buy coffee", false),
                    edited(None, "Buy coffee", false),
                ],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };
        let draft_ids = plan
            .operations
            .iter()
            .filter_map(|operation| match operation {
                Operation::Create { draft_id, .. } => Some(*draft_id),
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(draft_ids, [1, 2]);
    }

    #[test]
    fn creates_nested_tasks_with_draft_parent_references() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: Vec::new(),
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![
                    edited(None, "Parent", false),
                    EditedTask {
                        parent: Some(TaskReference::Draft(1)),
                        ..edited(None, "Child", false)
                    },
                ],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert!(plan.operations.iter().any(|operation| matches!(
            operation,
            Operation::Create {
                draft_id: 2,
                parent: Some(TaskReference::Draft(1)),
                parent_summary: Some(parent),
                ..
            } if parent == "Parent"
        )));
        assert!(format!("{plan}").contains("created   Child under Parent"));
    }

    #[test]
    fn deleting_a_parent_detaches_a_retained_child() {
        let parent = task("parent", "Parent");
        let child = Task {
            parent: Some(parent.id.clone()),
            ..task("child", "Child")
        };
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![parent, child],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![edited(Some("child"), "Child", false)],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert!(plan.operations.iter().any(|operation| matches!(
            operation,
            Operation::Delete { id, .. } if id.as_str() == "parent"
        )));
        assert!(plan.operations.iter().any(|operation| matches!(
            operation,
            Operation::Reparent { id, to: None, .. } if id.as_str() == "child"
        )));
        assert!(format!("{plan}").contains("detached  Child from Parent"));
    }

    #[test]
    fn marker_removal_plans_delete_and_create() {
        let baseline = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![task("a", "A")],
            }],
        };
        let markdown = EditedTaskState {
            lists: vec![EditedTaskList {
                name: "Personal".into(),
                tasks: vec![edited(None, "A", false)],
            }],
        };

        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &markdown, &baseline).unwrap()
        else {
            panic!("expected outgoing plan");
        };

        assert_eq!(plan.operations.len(), 2);
        assert!(
            plan.operations
                .iter()
                .any(|operation| matches!(operation, Operation::Delete { .. }))
        );
        assert!(
            plan.operations
                .iter()
                .any(|operation| matches!(operation, Operation::Create { .. }))
        );
    }
}
