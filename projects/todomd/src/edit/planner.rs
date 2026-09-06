use std::{collections::BTreeMap, fmt};

use anyhow::{Result, bail};
use serde::Serialize;

use crate::model::{EditedTaskState, TaskId, TaskState};

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
    Create {
        draft_id: usize,
        list: String,
        summary: String,
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
    let (markdown_tasks, new_tasks) = edited_task_map(markdown)?;

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

    Ok((identified, new))
}

fn operation_sort_key<'a>(
    operation: &'a Operation,
    list_positions: &BTreeMap<&str, usize>,
) -> (usize, u8, &'a str) {
    let (list, kind, summary) = match operation {
        Operation::Rename { list, to, .. } => (list.as_str(), 0, to.as_str()),
        Operation::Complete { list, summary, .. } => (list.as_str(), 1, summary.as_str()),
        Operation::Reopen { list, summary, .. } => (list.as_str(), 2, summary.as_str()),
        Operation::Create { list, summary, .. } => (list.as_str(), 3, summary.as_str()),
        Operation::Move { to, summary, .. } => (to.as_str(), 4, summary.as_str()),
        Operation::Delete { list, summary, .. } => (list.as_str(), 5, summary.as_str()),
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
                    Operation::Create { summary, .. } => {
                        writeln!(formatter, "  created   {summary}")?;
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
    use crate::model::{EditedTask, EditedTaskList, Task, TaskList};

    use super::*;

    fn task(id: &str, summary: &str) -> Task {
        Task {
            id: TaskId::new(id),
            summary: summary.into(),
            completed: false,
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
        }
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
