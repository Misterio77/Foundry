use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, Parser, Subcommand};
use todomd::{config::Config, edit, repository::Scope, show};

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
    /// Print tasks and their source files as JSON.
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

    /// Include completed and cancelled tasks.
    #[arg(long)]
    completed: bool,

    /// Whole VTODO lists to edit, in document order [default: every list].
    lists: Vec<String>,
}

#[derive(Args, Debug)]
struct ShowArgs {
    /// Include completed and cancelled tasks.
    #[arg(long)]
    completed: bool,

    /// Whole VTODO lists to print, in order [default: every list].
    lists: Vec<String>,
}

impl EditArgs {
    fn options(&self) -> edit::Options {
        edit::Options {
            no_hooks: self.no_hooks,
            keep: self.keep,
            scope: scope(self.completed),
        }
    }
}

fn scope(completed: bool) -> Scope {
    if completed { Scope::All } else { Scope::Active }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load(cli.config.as_deref())?;

    match cli.command {
        Some(Command::Edit(args)) => edit::run(&config, &args.lists, args.options()),
        Some(Command::Show(args)) => show::run(&config, &args.lists, scope(args.completed)),
        None => edit::run(&config, &[], edit::Options::default()),
    }
}
