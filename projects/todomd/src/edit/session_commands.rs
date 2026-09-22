use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

use super::{
    SessionOptions, applied_changes_message, create_session,
    hooks::Lifecycle,
    planner::ChangeCounts,
    session::{self, LoadedSession, TasksUpdate},
    session_reconcile::{self, Prepared},
};
use crate::{config::Config, model::TaskState};
use anyhow::{Context, Result, bail};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ApplyOutcome {
    NoChange,
    Inbound,
    Applied(ChangeCounts),
}

impl ApplyOutcome {
    pub fn message(&self) -> String {
        match self {
            Self::NoChange => "todomd: no changes".into(),
            Self::Inbound => "todomd: source changes loaded".into(),
            Self::Applied(counts) => applied_changes_message(*counts),
        }
    }
}

pub fn create(
    config: &Config,
    requested_lists: &[String],
    options: SessionOptions,
) -> Result<PathBuf> {
    let created = create_session(config, requested_lists, options)?;
    if let Some(warning) = created.warning {
        eprintln!("todomd: {warning}");
    }
    Ok(created.session.retain())
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
            let outcome = ApplyOutcome::Applied(outgoing.plan.counts());
            let applied = session_reconcile::apply(&context, outgoing)?;
            accept_state(&loaded, applied.state, applied.recovery)
                .context("source changes were applied, but the session could not be refreshed")?;

            let lifecycle =
                Lifecycle::live(&loaded.metadata.config.hooks, loaded.metadata.hooks_enabled);
            lifecycle.after_apply().context(
                "source changes and session were updated, but the after_apply hook failed",
            )?;
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

fn reconciliation_context(loaded: &LoadedSession) -> session_reconcile::Context<'_> {
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

fn accept_state(loaded: &LoadedSession, state: TaskState, recovery: TaskState) -> Result<()> {
    let accepted =
        session::render_accepted(&loaded.metadata.view, &loaded.manifest, state, recovery)
            .context("failed to render accepted session state")?;
    session::persist_accepted(&loaded.root, &accepted, TasksUpdate::ReplaceFile)
}
