use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, CommandFactory, Parser, Subcommand};
use clap_complete::{Shell, generate};
use todomd::{config::Config, edit, lsp, repository::Scope, show};

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    /// Use a specific configuration file.
    #[arg(long, global = true)]
    config: Option<PathBuf>,

    /// Generate a shell completion script.
    #[arg(long, value_enum, hide = true)]
    generate_completion: Option<Shell>,

    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Edit whole VTODO lists as Markdown.
    Edit(EditArgs),
    /// Print tasks and their source files as JSON.
    Show(ShowArgs),
    /// Run the language server over standard input/output.
    Lsp,
}

#[derive(Args, Debug)]
struct EditArgs {
    /// Disable the configured after_apply hook for this run.
    #[arg(long)]
    no_hooks: bool,

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
            scope: scope(self.completed),
        }
    }
}

fn scope(completed: bool) -> Scope {
    if completed { Scope::All } else { Scope::Active }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    if let Some(shell) = cli.generate_completion {
        generate(shell, &mut Cli::command(), "todomd", &mut std::io::stdout());
        return Ok(());
    }
    if matches!(cli.command, Some(Command::Lsp)) {
        return lsp::run();
    }
    let config = Config::load(cli.config.as_deref())?;

    match cli.command {
        Some(Command::Edit(args)) => edit::run(&config, &args.lists, args.options()),
        Some(Command::Show(args)) => show::run(&config, &args.lists, scope(args.completed)),
        Some(Command::Lsp) => unreachable!("LSP command handled before loading configuration"),
        None => edit::run(&config, &[], edit::Options::default()),
    }
}
