pub mod editor;
pub mod hooks;
pub mod live;
pub mod markdown;
pub mod planner;
pub mod session;
pub mod session_commands;
pub mod session_reconcile;
pub mod transaction;

use anyhow::Result;

use crate::view::View;
use crate::{
    config::Config,
    model::TaskState,
    repository::{self, Scope, SourceSnapshot, resolve_lists},
};
use hooks::Termination;
use markdown::{IdentityManifest, render_with_view};

#[derive(Clone, Debug)]
pub struct SessionOptions {
    pub hooks_enabled: bool,
    pub scope: Scope,
    pub view: View,
}

impl Default for SessionOptions {
    fn default() -> Self {
        Self {
            hooks_enabled: true,
            scope: Scope::default(),
            view: View::default(),
        }
    }
}

#[derive(Debug)]
pub struct RenderedSession {
    pub markdown: String,
    pub manifest: IdentityManifest,
    pub baseline: TaskState,
    pub sources: SourceSnapshot,
}

pub struct CreatedSession {
    pub session: session::Session,
    pub warning: Option<String>,
}

pub fn create_session(
    config: &Config,
    requested_lists: &[String],
    options: SessionOptions,
) -> Result<CreatedSession> {
    let lists = resolve_lists(config, requested_lists)?;
    let rendered = render_lists_with_view(config, &lists, options.scope, &options.view)?;
    let warning = rendered.sources.unrepresentable_warning();
    let recovery_baseline = if options.scope == Scope::All {
        rendered.baseline.clone()
    } else {
        repository::load_lists(config, &lists, Scope::All)?.0
    };
    let metadata = session::SessionMetadata {
        format_version: session::SESSION_FORMAT_VERSION,
        config: config.clone(),
        lists,
        scope: options.scope,
        hooks_enabled: options.hooks_enabled,
        view: options.view,
    };
    let session = session::Session::create(&rendered, &metadata, &recovery_baseline)?;
    Ok(CreatedSession { session, warning })
}

pub fn applied_changes_message(counts: planner::ChangeCounts) -> String {
    let counts = [
        (counts.created, "created"),
        (counts.updated, "updated"),
        (counts.deleted, "deleted"),
    ]
    .into_iter()
    .filter(|(count, _)| *count > 0)
    .map(|(count, operation)| format!("{count} {operation}"))
    .collect::<Vec<_>>()
    .join(", ");
    format!("todomd: changes applied ({counts})")
}

pub fn render_lists(
    config: &Config,
    requested_lists: &[String],
    scope: Scope,
) -> Result<RenderedSession> {
    let view = config.view(None)?;
    render_lists_with_view(config, requested_lists, scope, &view)
}

pub fn render_lists_with_view(
    config: &Config,
    requested_lists: &[String],
    scope: Scope,
    view: &View,
) -> Result<RenderedSession> {
    let (state, sources) = repository::load_lists(config, requested_lists, scope)?;
    let mut manifest = IdentityManifest::default();
    let markdown = render_with_view(&state, view, &mut manifest)?;

    Ok(RenderedSession {
        markdown,
        manifest,
        baseline: state,
        sources,
    })
}

/// Opens selected lists as a live Markdown document managed through LSP.
pub fn run(config: &Config, requested_lists: &[String], options: SessionOptions) -> Result<()> {
    let termination = Termination::install()?;
    let created = create_session(config, requested_lists, options)?;
    if let Some(warning) = created.warning {
        eprintln!("todomd: {warning}");
    }
    live::run(created.session, &termination)
}

#[cfg(test)]
mod tests {
    use super::{planner::ChangeCounts, *};

    #[test]
    fn applied_message_includes_only_nonzero_counts() {
        assert_eq!(
            applied_changes_message(ChangeCounts {
                created: 1,
                updated: 2,
                deleted: 0,
            }),
            "todomd: changes applied (1 created, 2 updated)"
        );
    }
}
