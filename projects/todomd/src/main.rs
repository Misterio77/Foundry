use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, Parser, Subcommand};
use todomd::{config::Config, edit, show};

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    /// Use a specific configuration file.
    #[arg(long, global = true)]
    config: Option<PathBuf>,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Edit whole VTODO lists as Markdown.
    Edit(EditArgs),
    /// Print active tasks and their source files as JSON.
    Show(ShowArgs),
}

#[derive(Args, Debug)]
struct EditArgs {
    /// Disable configured lifecycle hooks for this run.
    #[arg(long)]
    no_hooks: bool,

    /// Retain the session after an unchanged or successful run.
    #[arg(long)]
    keep: bool,

    /// Whole VTODO lists to edit, in document order [default: every list].
    lists: Vec<String>,
}

#[derive(Args, Debug)]
struct ShowArgs {
    /// Whole VTODO lists to print, in order [default: every list].
    lists: Vec<String>,
}

impl EditArgs {
    fn options(&self) -> edit::Options {
        edit::Options {
            no_hooks: self.no_hooks,
            keep: self.keep,
        }
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load(cli.config.as_deref())?;

    match cli.command {
        Some(Command::Edit(args)) => edit::run(&config, &args.lists, args.options()),
        Some(Command::Show(args)) => show::run(&config, &args.lists),
        None => edit::run(&config, &[], edit::Options::default()),
    }
}
