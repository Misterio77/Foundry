pub mod config;
pub mod edit;
pub mod editor;
pub mod hooks;
pub mod markdown;
pub mod model;
pub mod planner;
pub mod repository;
pub mod session;
pub mod show;
pub mod transaction;

use std::collections::BTreeSet;

use anyhow::{Result, bail};
use config::Config;
use markdown::{IdentityManifest, render};
use model::TaskState;
use repository::{SourceSnapshot, list_names, load_lists};

#[derive(Debug)]
pub struct RenderedSession {
    pub markdown: String,
    pub manifest: IdentityManifest,
    pub baseline: TaskState,
    pub sources: SourceSnapshot,
}

/// Resolves the lists a command operates on, defaulting to every discovered
/// list in display-name order.
pub fn resolve_lists(config: &Config, requested_lists: &[String]) -> Result<Vec<String>> {
    if requested_lists.is_empty() {
        return list_names(config);
    }

    let unique = requested_lists.iter().collect::<BTreeSet<_>>();
    if unique.len() != requested_lists.len() {
        bail!("list names must not be repeated");
    }

    Ok(requested_lists.to_vec())
}

pub fn render_lists(config: &Config, requested_lists: &[String]) -> Result<RenderedSession> {
    let (state, sources) = load_lists(config, requested_lists)?;
    let mut manifest = IdentityManifest::default();
    let markdown = render(&state, &mut manifest)?;

    Ok(RenderedSession {
        markdown,
        manifest,
        baseline: state,
        sources,
    })
}
