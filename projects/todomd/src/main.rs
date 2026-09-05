use std::path::PathBuf;

use anyhow::Result;
use clap::Parser;
use todomd::{config::Config, editor, render_lists, session::Session};

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
    let editor_result = editor::open(session.tasks_path());
    let retained = session.retain();

    eprintln!(
        "todomd: source files were not changed; session retained at {}",
        retained.display()
    );

    editor_result
}
