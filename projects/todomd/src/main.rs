use std::{io::Write, path::PathBuf};

use anyhow::{Context, Result};
use clap::Parser;
use todomd::{config::Config, render_lists};

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

    std::io::stdout()
        .write_all(rendered.markdown.as_bytes())
        .context("failed to write Markdown to stdout")
}
