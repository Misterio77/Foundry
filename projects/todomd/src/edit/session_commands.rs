use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

use super::{
    Options,
    hooks::Lifecycle,
    markdown,
    planner::TaskChange,
    session::{self, LiveMetadata, LoadedLiveSession, Session},
    session_reconcile::{self, Prepared},
};
use crate::{
    config::Config,
    model::TaskState,
    repository::{self, Scope, resolve_lists},
};
use anyhow::{Context, Result, bail};

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
    let context = reconciliation_context(&loaded);
    match session_reconcile::prepare(&context, &text, &BTreeSet::new())? {
        Prepared::NoChange { baseline } => {
            let recovery = session_reconcile::load_recovery(&context)?;
            accept_state(&loaded, baseline, recovery)?;
            Ok(ApplyOutcome::NoChange)
        }
        Prepared::Inbound { current } => {
            let recovery = session_reconcile::load_recovery(&context)?;
            accept_state(&loaded, current, recovery)?;
            Ok(ApplyOutcome::Inbound)
        }
        Prepared::Conflict => {
            bail!("Markdown and source lists both changed; session was left untouched")
        }
        Prepared::Outgoing(outgoing) => {
            let outcome = applied_outcome(&outgoing.plan.changes);
            let applied = session_reconcile::apply(&context, outgoing)?;
            accept_state(&loaded, applied.state, applied.recovery)
                .context("source changes were applied, but the session could not be refreshed")?;

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

fn reconciliation_context(loaded: &LoadedLiveSession) -> session_reconcile::Context<'_> {
    session_reconcile::Context {
        root: &loaded.root,
        config: &loaded.metadata.config,
        lists: &loaded.metadata.lists,
        scope: loaded.metadata.scope,
        view: &loaded.metadata.view,
        baseline: &loaded.baseline,
        recovery_baseline: &loaded.recovery_baseline,
        manifest: &loaded.manifest,
    }
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
