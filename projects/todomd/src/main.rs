use std::path::PathBuf;

use anyhow::{Result, bail};
use clap::Parser;
use todomd::{
    config::Config,
    editor, markdown,
    planner::{self, Reconciliation},
    render_lists, repository,
    session::Session,
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
        let (current_ics, _) = repository::load_lists(&config, &cli.lists)?;
        planner::reconcile(&rendered.baseline, &edited, &current_ics)
    })();

    match reconciliation {
        Ok(Reconciliation::NoChange) => {
            eprintln!("todomd: no changes");
            Ok(())
        }
        Ok(Reconciliation::Outgoing(plan)) => {
            print!("{plan}");
            retain_and_report(session);
            eprintln!("todomd: preview only; source files were not changed");
            Ok(())
        }
        Ok(Reconciliation::Inbound) => {
            retain_and_report(session);
            bail!("source lists changed while the editor was open")
        }
        Ok(Reconciliation::Conflict) => {
            retain_and_report(session);
            bail!("Markdown and source lists both changed while the editor was open")
        }
        Err(error) => {
            retain_and_report(session);
            Err(error)
        }
    }
}

fn retain_and_report(session: Session) {
    let retained = session.retain();
    eprintln!("todomd: session retained at {}", retained.display());
}
