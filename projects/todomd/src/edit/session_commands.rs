use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use chrono::Utc;

use super::{
    Options,
    hooks::Lifecycle,
    markdown,
    planner::{self, Reconciliation, TaskChange},
    session::{self, LiveMetadata, LoadedLiveSession, Session},
    transaction,
};
use crate::{
    config::Config,
    model::{EditedTaskState, TaskId, TaskState},
    repository::{self, Scope, SourceSnapshot, resolve_lists},
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ApplyOutcome {
    NoChange,
    Inbound,
    Applied {
        created: usize,
        updated: usize,
        deleted: usize,
    },
}

impl ApplyOutcome {
    pub fn message(&self) -> String {
        match self {
            Self::NoChange => "todomd: no changes".into(),
            Self::Inbound => "todomd: source changes loaded".into(),
            Self::Applied {
                created,
                updated,
                deleted,
            } => {
                let counts = [
                    (*created, "created"),
                    (*updated, "updated"),
                    (*deleted, "deleted"),
                ]
                .into_iter()
                .filter(|(count, _)| *count > 0)
                .map(|(count, operation)| format!("{count} {operation}"))
                .collect::<Vec<_>>()
                .join(", ");
                format!("todomd: changes applied ({counts})")
            }
        }
    }
}

pub fn create(config: &Config, requested_lists: &[String], options: Options) -> Result<PathBuf> {
    let lists = resolve_lists(config, requested_lists)?;
    let rendered = super::render_lists_with_view(config, &lists, options.scope, &options.view)?;
    if let Some(warning) = rendered.sources.unrepresentable_warning() {
        eprintln!("todomd: {warning}");
    }
    let recovery_baseline = if options.scope == Scope::All {
        rendered.baseline.clone()
    } else {
        repository::load_lists(config, &lists, Scope::All)?.0
    };
    let metadata = LiveMetadata {
        format_version: session::LIVE_FORMAT_VERSION,
        config: config.clone(),
        lists,
        scope: options.scope,
        hooks_enabled: !options.no_hooks,
        view: options.view,
    };
    let session = Session::create_live(&rendered, &metadata, &recovery_baseline)?;
    Ok(session.retain())
}

pub fn apply(root: &Path) -> Result<ApplyOutcome> {
    session::validate_root(root)?;
    let _lock = session::lock(root)?;
    let loaded = session::load(root)?;
    let text = fs::read_to_string(root.join("tasks.md"))
        .with_context(|| format!("failed to read {}", root.join("tasks.md").display()))?;
    let edited = markdown::parse_with_view(
        &text,
        &loaded.baseline,
        &loaded.manifest,
        &loaded.metadata.view,
    )?;
    let (baseline, mut required_tasks) = reconciliation_baseline(&loaded, &edited);
    required_tasks.extend(completed_roots(&loaded));
    let (current, sources) = load_current(&loaded, &required_tasks)?;

    match planner::reconcile(&baseline, &edited, &current)? {
        Reconciliation::NoChange => {
            let recovery = load_recovery(&loaded)?;
            accept_state(&loaded, baseline, recovery)?;
            Ok(ApplyOutcome::NoChange)
        }
        Reconciliation::Inbound => {
            let recovery = load_recovery(&loaded)?;
            accept_state(&loaded, current, recovery)?;
            Ok(ApplyOutcome::Inbound)
        }
        Reconciliation::Conflict => {
            bail!("Markdown and source lists both changed; session was left untouched")
        }
        Reconciliation::Outgoing(plan) => {
            for change in &plan.changes {
                if let TaskChange::Update { id, before, after } = change
                    && !before.completed
                    && after.completed
                {
                    required_tasks.insert(id.clone());
                }
            }
            let staged = transaction::stage(&plan, &sources, root, Utc::now())?;
            transaction::apply(&staged, &sources)?;
            let (accepted, accepted_sources) = load_current(&loaded, &required_tasks)
                .context("source changes were applied, but the accepted state could not be read")?;
            transaction::verify_applied(&staged, &sources, &accepted_sources).context(
                "source changes were applied, but concurrent changes prevented acceptance",
            )?;
            let recovery = load_recovery(&loaded)
                .context("source changes were applied, but recovery state could not be read")?;
            accept_state(&loaded, accepted, recovery)
                .context("source changes were applied, but the session could not be refreshed")?;

            let outcome = applied_outcome(&plan.changes);
            let lifecycle =
                Lifecycle::live(&loaded.metadata.config.hooks, loaded.metadata.hooks_enabled);
            lifecycle.after_apply()?;
            Ok(outcome)
        }
    }
}

pub fn close(root: &Path, force: bool) -> Result<()> {
    session::validate_root(root)?;
    let _lock = session::lock(root)?;
    let loaded = session::load(root)?;
    let tasks = fs::read(root.join("tasks.md"))
        .with_context(|| format!("failed to read {}", root.join("tasks.md").display()))?;
    if !force && tasks != loaded.accepted_text.as_bytes() {
        bail!("session has unapplied changes; apply it or use --force to discard them")
    }
    fs::remove_dir_all(root).with_context(|| format!("failed to close session {}", root.display()))
}

fn reconciliation_baseline(
    loaded: &LoadedLiveSession,
    edited: &EditedTaskState,
) -> (TaskState, BTreeSet<TaskId>) {
    let required_tasks = identities_outside(edited, &loaded.baseline);
    let mut baseline = loaded.baseline.clone();
    add_tasks(&mut baseline, &loaded.recovery_baseline, &required_tasks);
    (baseline, required_tasks)
}

fn completed_roots(loaded: &LoadedLiveSession) -> BTreeSet<TaskId> {
    if loaded.metadata.scope == Scope::All {
        return BTreeSet::new();
    }
    loaded
        .baseline
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .filter(|task| task.completed && task.parent.is_none())
        .map(|task| task.id.clone())
        .collect()
}

fn load_current(
    loaded: &LoadedLiveSession,
    required_tasks: &BTreeSet<TaskId>,
) -> Result<(TaskState, SourceSnapshot)> {
    let (mut current, sources) = repository::load_lists(
        &loaded.metadata.config,
        &loaded.metadata.lists,
        loaded.metadata.scope,
    )?;
    if loaded.metadata.scope == Scope::All || required_tasks.is_empty() {
        return Ok((current, sources));
    }

    let (current_all, sources) =
        repository::load_lists(&loaded.metadata.config, &loaded.metadata.lists, Scope::All)?;
    add_tasks(&mut current, &current_all, required_tasks);
    Ok((current, sources))
}

fn load_recovery(loaded: &LoadedLiveSession) -> Result<TaskState> {
    Ok(repository::load_lists(&loaded.metadata.config, &loaded.metadata.lists, Scope::All)?.0)
}

fn accept_state(loaded: &LoadedLiveSession, state: TaskState, recovery: TaskState) -> Result<()> {
    let mut manifest = loaded.manifest.clone();
    let text = markdown::render_with_view(&state, &loaded.metadata.view, &mut manifest)?;
    session::accept_manual(&loaded.root, &text, &manifest, &state, &recovery)
}

fn applied_outcome(changes: &[TaskChange]) -> ApplyOutcome {
    let (mut created, mut updated, mut deleted) = (0, 0, 0);
    for change in changes {
        match change {
            TaskChange::Create { .. } => created += 1,
            TaskChange::Update { .. } => updated += 1,
            TaskChange::Delete { .. } => deleted += 1,
        }
    }
    ApplyOutcome::Applied {
        created,
        updated,
        deleted,
    }
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
