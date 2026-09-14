use std::time::{Duration, Instant};

use anyhow::{Result, bail};

use super::{RenderedSession, editor, session::LiveMetadata, session::Session};
use crate::{config::Config, repository, repository::Scope};

const ATTACH_TIMEOUT: Duration = Duration::from_secs(10);

pub fn run(
    config: &Config,
    lists: &[String],
    scope: Scope,
    hooks_enabled: bool,
    termination: &super::hooks::Termination,
) -> Result<()> {
    termination.check()?;
    let rendered = super::render_lists(config, lists, scope)?;
    if let Some(warning) = rendered.sources.unrepresentable_warning() {
        eprintln!("todomd: {warning}");
    }
    let recovery_baseline = recovery_baseline(config, lists, scope, &rendered)?;
    let metadata = LiveMetadata {
        config: config.clone(),
        lists: lists.to_vec(),
        scope,
        hooks_enabled,
    };
    let session = Session::create_live(&rendered, &metadata, &recovery_baseline)?;
    let started = Instant::now();

    let result = editor::open_live(
        session.tasks_path(),
        || termination.is_requested(),
        || {
            if !session.is_attached() && started.elapsed() >= ATTACH_TIMEOUT {
                bail!(
                    "editor did not attach todomd lsp within {} seconds",
                    ATTACH_TIMEOUT.as_secs()
                );
            }
            Ok(())
        },
    );
    let result = result.and_then(|()| {
        termination.check()?;
        if !session.is_attached() {
            bail!("editor closed before todomd lsp attached");
        }
        Ok(())
    });

    let retained = session.retain();
    eprintln!("todomd: live session retained at {}", retained.display());
    result
}

fn recovery_baseline(
    config: &Config,
    lists: &[String],
    scope: Scope,
    rendered: &RenderedSession,
) -> Result<crate::model::TaskState> {
    if scope == Scope::All {
        return Ok(rendered.baseline.clone());
    }
    Ok(repository::load_lists(config, lists, Scope::All)?.0)
}
