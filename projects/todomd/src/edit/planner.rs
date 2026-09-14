use std::collections::BTreeMap;

use crate::{
    dates::{self, DateValue},
    model::{EditedTaskState, Priority, TaskId, TaskReference, TaskState},
};
use anyhow::{Context, Result, bail};
use serde::Serialize;

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ChangePlan {
    pub changes: Vec<TaskChange>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Reconciliation {
    NoChange,
    Outgoing(ChangePlan),
    Inbound,
    Conflict,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PlannedTask {
    pub list: String,
    pub summary: String,
    pub completed: bool,
    pub priority: Priority,
    pub categories: Vec<String>,
    pub parent: Option<TaskReference>,
    pub start: Option<DateValue>,
    pub due: Option<DateValue>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub enum TaskChange {
    Create {
        draft_id: usize,
        task: PlannedTask,
    },
    Update {
        id: TaskId,
        before: PlannedTask,
        after: PlannedTask,
    },
    Delete {
        id: TaskId,
        task: PlannedTask,
    },
}

type IdentifiedTasks = BTreeMap<TaskId, PlannedTask>;
type DraftTasks = BTreeMap<usize, PlannedTask>;

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
    for task in new_tasks.values() {
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
            &baseline_tasks,
            &markdown_tasks,
            &new_tasks,
        ))),
    }
}

fn build_plan(
    baseline_tasks: &IdentifiedTasks,
    markdown_tasks: &IdentifiedTasks,
    new_tasks: &DraftTasks,
) -> ChangePlan {
    let mut changes = Vec::new();
    for (id, before) in baseline_tasks {
        match markdown_tasks.get(id) {
            Some(after) if before != after => changes.push(TaskChange::Update {
                id: id.clone(),
                before: before.clone(),
                after: after.clone(),
            }),
            None => changes.push(TaskChange::Delete {
                id: id.clone(),
                task: before.clone(),
            }),
            Some(_) => {}
        }
    }
    changes.extend(new_tasks.iter().map(|(draft_id, task)| TaskChange::Create {
        draft_id: *draft_id,
        task: task.clone(),
    }));

    ChangePlan { changes }
}

fn task_map(state: &TaskState) -> IdentifiedTasks {
    state
        .lists
        .iter()
        .flat_map(|list| {
            list.tasks.iter().map(|task| {
                (
                    task.id.clone(),
                    PlannedTask {
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
    let mut new = BTreeMap::new();
    let mut next_draft_id = 1;

    for list in &state.lists {
        for task in &list.tasks {
            let comparable = PlannedTask {
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
                    new.insert(next_draft_id, comparable);
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
    for task in new_tasks.values_mut() {
        dates::normalize_and_validate(&mut task.start, &mut task.due)
            .with_context(|| format!("invalid dates for new task {:?}", task.summary))?;
    }
    Ok(())
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

        assert!(matches!(
            &plan.changes[..],
            [TaskChange::Create { draft_id: 1, task }]
                if task.list == "Postgrad"
                    && task.summary == "Foo"
                    && task.priority == Priority::High
        ));
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

        assert!(matches!(
            &plan.changes[..],
            [TaskChange::Update { id, before, after }]
                if id.as_str() == "paper"
                    && before.priority == Priority::High
                    && after.priority == Priority::Low
        ));
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

        assert!(matches!(
            &plan.changes[..],
            [TaskChange::Update { id, before, after }]
                if id.as_str() == "paper"
                    && before.categories == ["Old"]
                    && after.categories == ["New", "Quick Win"]
        ));
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
        assert!(matches!(
            &plan.changes[..],
            [TaskChange::Update { after, .. }]
                if matches!(after.start, Some(DateValue::DateTime(_)))
                    && matches!(after.due, Some(DateValue::DateTime(_)))
        ));
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
        assert!(matches!(
            &plan.changes[..],
            [TaskChange::Update { before, after, .. }]
                if before.summary == "Write paper"
                    && after.summary == "Rename only"
                    && before.start == after.start
                    && before.due == after.due
        ));
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

        assert!(matches!(
            &plan.changes[..],
            [TaskChange::Update { id, before, after }]
                if id.as_str() == "read" && before.completed && !after.completed
        ));
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
    fn combines_field_edits_into_task_changes() {
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

        assert_eq!(plan.changes.len(), 3);
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            TaskChange::Update { id, before, after }
                if id.as_str() == "paper"
                    && before.list == "Postgrad"
                    && after.list == "Personal"
                    && after.summary == "Submit paper"
                    && after.completed
        )));
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            TaskChange::Delete { id, .. } if id.as_str() == "old"
        )));
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            TaskChange::Create { task, .. } if task.summary == "Buy coffee"
        )));
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
            .changes
            .iter()
            .filter_map(|change| match change {
                TaskChange::Create { draft_id, .. } => Some(*draft_id),
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

        assert!(plan.changes.iter().any(|change| matches!(
            change,
            TaskChange::Create { draft_id: 2, task }
                if task.parent == Some(TaskReference::Draft(1))
                    && task.summary == "Child"
        )));
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

        assert!(plan.changes.iter().any(|change| matches!(
            change,
            TaskChange::Delete { id, .. } if id.as_str() == "parent"
        )));
        assert!(plan.changes.iter().any(|change| matches!(
            change,
            TaskChange::Update { id, before, after }
                if id.as_str() == "child" && before.parent.is_some() && after.parent.is_none()
        )));
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

        assert_eq!(plan.changes.len(), 2);
        assert!(
            plan.changes
                .iter()
                .any(|change| matches!(change, TaskChange::Delete { .. }))
        );
        assert!(
            plan.changes
                .iter()
                .any(|change| matches!(change, TaskChange::Create { .. }))
        );
    }
}
