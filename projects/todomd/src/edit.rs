use std::io::{self, Write};

use anyhow::{Context, Result, anyhow, bail};
use chrono::Utc;

use crate::{
    config::Config,
    editor,
    hooks::{Lifecycle, Termination},
    markdown,
    planner::{self, Reconciliation},
    render_lists, repository, resolve_lists,
    session::Session,
    transaction,
};

#[derive(Clone, Copy, Debug, Default)]
pub struct Options {
    pub no_hooks: bool,
    pub keep: bool,
}

/// Renders the selected lists, opens them in an editor, and applies confirmed
/// changes back to the source vdirs.
pub fn run(config: &Config, requested_lists: &[String], options: Options) -> Result<()> {
    let lists = resolve_lists(config, requested_lists)?;
    let termination = Termination::install()?;
    let lifecycle = Lifecycle::start(&config.hooks, !options.no_hooks)?;
    let result = session(config, &lists, options.keep, &lifecycle, &termination);
    let result = lifecycle.finish(result);
    if result.is_ok() {
        termination.check()?;
    }
    result
}

fn session(
    config: &Config,
    lists: &[String],
    keep: bool,
    lifecycle: &Lifecycle,
    termination: &Termination,
) -> Result<()> {
    termination.check()?;
    let rendered = render_lists(config, lists)?;
    let session = Session::create(&rendered)?;

    if let Err(error) = editor::open(session.tasks_path(), || termination.is_requested()) {
        retain_and_report(session);
        return Err(error);
    }
    if let Err(error) = termination.check() {
        retain_and_report(session);
        return Err(error);
    }

    let reconciliation = (|| {
        let edited_document = session.read_tasks()?;
        let edited = markdown::parse(&edited_document, &rendered.baseline, &rendered.manifest)?;
        let (current_ics, sources) = repository::load_lists(config, lists)?;
        Ok((
            planner::reconcile(&rendered.baseline, &edited, &current_ics)?,
            sources,
        ))
    })();

    let (reconciliation, sources) = match reconciliation {
        Ok(value) => value,
        Err(error) => {
            retain_and_report(session);
            return Err(error);
        }
    };

    if let Err(error) = termination.check() {
        retain_and_report(session);
        return Err(error);
    }

    match reconciliation {
        Reconciliation::NoChange => {
            eprintln!("todomd: no changes");
            retain_if_requested(session, keep);
            Ok(())
        }
        Reconciliation::Outgoing(plan) => {
            let staged = match transaction::stage(&plan, &sources, session.path(), Utc::now()) {
                Ok(staged) => staged,
                Err(error) => {
                    retain_and_report(session);
                    return Err(error);
                }
            };
            if let Err(error) = write_preview(&plan, &staged) {
                retain_and_report(session);
                return Err(error);
            }

            if let Err(error) = termination.check() {
                retain_and_report(session);
                return Err(error);
            }

            let confirmed = match transaction::confirm(|| termination.is_requested()) {
                Ok(confirmed) => confirmed,
                Err(error) => {
                    retain_and_report(session);
                    return Err(error);
                }
            };

            if !confirmed {
                retain_and_report(session);
                eprintln!("todomd: changes cancelled; source files were not changed");
                return Ok(());
            }
            if let Err(error) = termination.check() {
                retain_and_report(session);
                return Err(error);
            }

            if let Err(error) = transaction::apply(&staged, &sources) {
                retain_and_report(session);
                return Err(error);
            }

            let refresh = refresh_accepted_session(&session, &rendered.manifest, config, lists);
            let hook = lifecycle.after_apply();
            if let Err(error) = combine_post_apply(refresh, hook) {
                retain_and_report(session);
                return Err(error);
            }
            if let Err(error) = termination.check() {
                retain_and_report(session);
                return Err(error);
            }

            eprintln!("todomd: changes applied");
            retain_if_requested(session, keep);
            Ok(())
        }
        Reconciliation::Inbound => {
            retain_and_report(session);
            bail!("source lists changed while the editor was open")
        }
        Reconciliation::Conflict => {
            retain_and_report(session);
            bail!("Markdown and source lists both changed while the editor was open")
        }
    }
}

fn write_preview(
    plan: &planner::ChangePlan,
    staged: &transaction::StagedTransaction,
) -> Result<()> {
    let mut stdout = io::stdout().lock();
    write!(stdout, "{plan}\n{staged}").context("failed to write change preview")?;
    stdout.flush().context("failed to flush change preview")
}

fn refresh_accepted_session(
    session: &Session,
    manifest: &markdown::IdentityManifest,
    config: &Config,
    lists: &[String],
) -> Result<()> {
    let (accepted, _) = repository::load_lists(config, lists)
        .context("source changes were applied, but the accepted state could not be read")?;
    let mut manifest = manifest.clone();
    let document = markdown::render(&accepted, &mut manifest)
        .context("source changes were applied, but the accepted state could not be rendered")?;
    session
        .accept(&document, &manifest, &accepted)
        .context("source changes were applied, but the session could not be refreshed")
}

fn combine_post_apply(refresh: Result<()>, hook: Result<()>) -> Result<()> {
    match (refresh, hook) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
        (Err(refresh), Err(hook)) => Err(anyhow!(
            "{refresh:#}; after_apply hook also failed: {hook:#}"
        )),
    }
}

fn retain_if_requested(session: Session, keep: bool) {
    if keep {
        retain_and_report(session);
    }
}

fn retain_and_report(session: Session) {
    let retained = session.retain();
    eprintln!("todomd: session retained at {}", retained.display());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn post_apply_reports_both_failures() {
        let error = combine_post_apply(Err(anyhow!("refresh failed")), Err(anyhow!("hook failed")))
            .unwrap_err();

        let message = format!("{error:#}");
        assert!(message.contains("refresh failed"));
        assert!(message.contains("after_apply hook also failed"));
    }

    #[test]
    fn post_apply_succeeds_only_when_both_succeed() {
        assert!(combine_post_apply(Ok(()), Ok(())).is_ok());
        assert!(combine_post_apply(Err(anyhow!("refresh")), Ok(())).is_err());
        assert!(combine_post_apply(Ok(()), Err(anyhow!("hook"))).is_err());
    }
}
