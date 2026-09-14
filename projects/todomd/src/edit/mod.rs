pub mod editor;
pub mod hooks;
pub mod live;
pub mod markdown;
pub mod planner;
pub mod session;
pub mod transaction;

use anyhow::Result;

use crate::{
    config::Config,
    model::TaskState,
    repository::{self, Scope, SourceSnapshot, resolve_lists},
};
use hooks::Termination;
use markdown::{IdentityManifest, render};

#[derive(Clone, Copy, Debug, Default)]
pub struct Options {
    pub no_hooks: bool,
    pub scope: Scope,
}

#[derive(Debug)]
pub struct RenderedSession {
    pub markdown: String,
    pub manifest: IdentityManifest,
    pub baseline: TaskState,
    pub sources: SourceSnapshot,
}

pub fn render_lists(
    config: &Config,
    requested_lists: &[String],
    scope: Scope,
) -> Result<RenderedSession> {
    let (state, sources) = repository::load_lists(config, requested_lists, scope)?;
    let mut manifest = IdentityManifest::default();
    let markdown = render(&state, &mut manifest)?;

    Ok(RenderedSession {
        markdown,
        manifest,
        baseline: state,
        sources,
    })
}

/// Opens selected lists as a live Markdown document managed through LSP.
pub fn run(config: &Config, requested_lists: &[String], options: Options) -> Result<()> {
    let lists = resolve_lists(config, requested_lists)?;
    let termination = Termination::install()?;
    live::run(
        config,
        &lists,
        options.scope,
        !options.no_hooks,
        &termination,
    )
}
