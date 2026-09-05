pub mod config;
pub mod markdown;
pub mod model;
pub mod repository;

use std::collections::BTreeSet;

use anyhow::{Result, bail};
use config::Config;
use markdown::{IdentityManifest, render};
use repository::{SourceSnapshot, load_lists};

#[derive(Debug)]
pub struct RenderedSession {
    pub markdown: String,
    pub manifest: IdentityManifest,
    pub sources: SourceSnapshot,
}

pub fn render_lists(config: &Config, requested_lists: &[String]) -> Result<RenderedSession> {
    if requested_lists.is_empty() {
        bail!("at least one list is required");
    }

    let unique = requested_lists.iter().collect::<BTreeSet<_>>();
    if unique.len() != requested_lists.len() {
        bail!("list names must not be repeated");
    }

    let (state, sources) = load_lists(config, requested_lists)?;
    let mut manifest = IdentityManifest::default();
    let markdown = render(&state, &mut manifest)?;

    Ok(RenderedSession {
        markdown,
        manifest,
        sources,
    })
}
