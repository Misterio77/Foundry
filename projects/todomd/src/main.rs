use std::{
    io::{self, Write},
    path::PathBuf,
};

use anyhow::{Context, Result, bail};
use chrono::Utc;
use clap::Parser;
use todomd::{
    config::Config,
    editor, markdown,
    planner::{self, Reconciliation},
    render_lists, repository,
    session::Session,
    transaction,
};

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    /// Use a specific configuration file.
    #[arg(long)]
    config: Option<PathBuf>,

    /// Whole VTODO lists to render, in document order.
    #[arg(required = true)]
    lists: Vec<String>,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load(cli.config.as_deref())?;
    let rendered = render_lists(&config, &cli.lists)?;
    let session = Session::create(&rendered)?;

    if let Err(error) = editor::open(session.tasks_path()) {
        retain_and_report(session);
        return Err(error);
    }

    let reconciliation = (|| {
        let edited_document = session.read_tasks()?;
        let edited = markdown::parse(&edited_document, &rendered.baseline, &rendered.manifest)?;
        let (current_ics, sources) = repository::load_lists(&config, &cli.lists)?;
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

    match reconciliation {
        Reconciliation::NoChange => {
            eprintln!("todomd: no changes");
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

            let confirmed = match transaction::confirm() {
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

            if let Err(error) = transaction::apply(&staged, &sources) {
                retain_and_report(session);
                return Err(error);
            }

            eprintln!("todomd: changes applied");
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

fn retain_and_report(session: Session) {
    let retained = session.retain();
    eprintln!("todomd: session retained at {}", retained.display());
}
