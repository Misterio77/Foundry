use std::{collections::BTreeSet, path::Path};

use anyhow::{Context as _, Result};
use chrono::Utc;

use super::{
    markdown::{self, IdentityManifest},
    planner::{self, ChangePlan, Reconciliation, TaskChange},
    transaction,
};
use crate::{
    config::Config,
    model::{EditedTaskState, TaskId, TaskState},
    repository::{self, Scope, SourceSnapshot},
    view::View,
};

pub struct Context<'a> {
    pub root: &'a Path,
    pub config: &'a Config,
    pub lists: &'a [String],
    pub scope: Scope,
    pub view: &'a View,
    pub baseline: &'a TaskState,
    pub recovery_baseline: &'a TaskState,
    pub manifest: &'a IdentityManifest,
}

pub enum Prepared {
    NoChange { baseline: TaskState },
    Inbound { current: TaskState },
    Outgoing(Outgoing),
    Conflict,
}

pub struct Outgoing {
    pub plan: ChangePlan,
    sources: SourceSnapshot,
    retained_tasks: BTreeSet<TaskId>,
}

pub struct Applied {
    pub state: TaskState,
    pub recovery: TaskState,
    pub retained_tasks: BTreeSet<TaskId>,
}

pub fn validate(context: &Context<'_>, text: &str) -> Result<()> {
    let edited = parse(context, text)?;
    let (baseline, _) = reconciliation_baseline(context, &edited);
    planner::reconcile(&baseline, &edited, &baseline)?;
    Ok(())
}

pub fn prepare(
    context: &Context<'_>,
    text: &str,
    retained_tasks: &BTreeSet<TaskId>,
) -> Result<Prepared> {
    let edited = parse(context, text)?;
    let (baseline, mut required_tasks) = reconciliation_baseline(context, &edited);
    required_tasks.extend(completed_roots(context));
    required_tasks.extend(retained_tasks.iter().cloned());
    let (current, sources) = load_current(context, &required_tasks)?;

    Ok(match planner::reconcile(&baseline, &edited, &current)? {
        Reconciliation::NoChange => Prepared::NoChange { baseline },
        Reconciliation::Inbound => Prepared::Inbound { current },
        Reconciliation::Outgoing(plan) => Prepared::Outgoing(Outgoing {
            plan,
            sources,
            retained_tasks: required_tasks,
        }),
        Reconciliation::Conflict => Prepared::Conflict,
    })
}

pub fn apply(context: &Context<'_>, mut outgoing: Outgoing) -> Result<Applied> {
    for change in &outgoing.plan.changes {
        if let TaskChange::Update { id, before, after } = change
            && !before.completed
            && after.completed
        {
            outgoing.retained_tasks.insert(id.clone());
        }
    }

    let staged = transaction::stage(&outgoing.plan, &outgoing.sources, context.root, Utc::now())?;
    transaction::apply(&staged, &outgoing.sources)?;
    let (state, accepted_sources) = load_current(context, &outgoing.retained_tasks)
        .context("source changes were applied, but the accepted state could not be read")?;
    transaction::verify_applied(&staged, &outgoing.sources, &accepted_sources)
        .context("source changes were applied, but concurrent changes prevented acceptance")?;
    let recovery = load_recovery(context)
        .context("source changes were applied, but recovery state could not be read")?;

    Ok(Applied {
        state,
        recovery,
        retained_tasks: outgoing.retained_tasks,
    })
}

pub fn load_recovery(context: &Context<'_>) -> Result<TaskState> {
    Ok(repository::load_lists(context.config, context.lists, Scope::All)?.0)
}

fn parse(context: &Context<'_>, text: &str) -> Result<EditedTaskState> {
    markdown::parse_with_view(text, context.baseline, context.manifest, context.view)
}

fn reconciliation_baseline(
    context: &Context<'_>,
    edited: &EditedTaskState,
) -> (TaskState, BTreeSet<TaskId>) {
    let required_tasks = identities_outside(edited, context.baseline);
    let mut baseline = context.baseline.clone();
    add_tasks(&mut baseline, context.recovery_baseline, &required_tasks);
    (baseline, required_tasks)
}

fn completed_roots(context: &Context<'_>) -> BTreeSet<TaskId> {
    if context.scope == Scope::All {
        return BTreeSet::new();
    }
    context
        .baseline
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .filter(|task| task.completed && task.parent.is_none())
        .map(|task| task.id.clone())
        .collect()
}

fn load_current(
    context: &Context<'_>,
    required_tasks: &BTreeSet<TaskId>,
) -> Result<(TaskState, SourceSnapshot)> {
    let (mut current, sources) =
        repository::load_lists(context.config, context.lists, context.scope)?;
    if context.scope == Scope::All || required_tasks.is_empty() {
        return Ok((current, sources));
    }

    let (current_all, sources) = repository::load_lists(context.config, context.lists, Scope::All)?;
    add_tasks(&mut current, &current_all, required_tasks);
    Ok((current, sources))
}

fn identities_outside(edited: &EditedTaskState, baseline: &TaskState) -> BTreeSet<TaskId> {
    let baseline_ids = baseline
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .map(|task| &task.id)
        .collect::<BTreeSet<_>>();
    edited
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .filter_map(|task| task.id.as_ref())
        .filter(|id| !baseline_ids.contains(id))
        .cloned()
        .collect()
}

fn add_tasks(target: &mut TaskState, source: &TaskState, ids: &BTreeSet<TaskId>) {
    for source_list in &source.lists {
        let Some(target_list) = target
            .lists
            .iter_mut()
            .find(|list| list.name == source_list.name)
        else {
            continue;
        };
        for task in &source_list.tasks {
            if ids.contains(&task.id) && !target_list.tasks.iter().any(|item| item.id == task.id) {
                target_list.tasks.push(task.clone());
            }
        }
    }
}
