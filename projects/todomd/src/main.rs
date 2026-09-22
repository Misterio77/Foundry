use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, CommandFactory, Parser, Subcommand};
use clap_complete::{Shell, generate};
use todomd::{
    config::Config,
    edit, lsp,
    repository::Scope,
    show,
    view::{GroupKey, SortKey, View},
};

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

#[derive(Args, Clone, Debug, Default)]
struct ViewArgs {
    /// Use a configured named view.
    #[arg(long, value_name = "NAME")]
    view: Option<String>,

    /// Group roots by these comma-separated fields.
    #[arg(long, value_delimiter = ',', conflicts_with = "no_group")]
    group_by: Option<Vec<GroupKey>>,

    /// Render roots without group headings.
    #[arg(long)]
    no_group: bool,

    /// Sort siblings by these comma-separated fields.
    #[arg(long, value_delimiter = ',')]
    sort_by: Option<Vec<SortKey>>,
}

impl ViewArgs {
    fn resolve(&self, config: &Config) -> Result<View> {
        let mut view = config.view(self.view.as_deref())?;
        if self.no_group {
            view.group_by.clear();
        } else if let Some(group_by) = &self.group_by {
            view.group_by.clone_from(group_by);
        }
        if let Some(sort_by) = &self.sort_by {
            view.sort_by.clone_from(sort_by);
        }
        view.validate("command-line view")?;
        Ok(view)
    }
}

#[derive(Args, Debug)]
struct EditArgs {
    /// Disable the configured after_apply hook for this run.
    #[arg(long)]
    no_hooks: bool,

    /// Include completed and cancelled tasks.
    #[arg(long)]
    completed: bool,

    #[command(flatten)]
    view: ViewArgs,

    /// Whole VTODO lists to edit, in document order [default: every list].
    lists: Vec<String>,
}

#[derive(Args, Debug)]
struct ShowArgs {
    /// Include completed and cancelled tasks.
    #[arg(long)]
    completed: bool,

    #[command(flatten)]
    view: ViewArgs,

    /// Whole VTODO lists to print, in order [default: every list].
    lists: Vec<String>,
}

impl EditArgs {
    fn options(&self, config: &Config) -> Result<edit::Options> {
        Ok(edit::Options {
            no_hooks: self.no_hooks,
            scope: scope(self.completed),
            view: self.view.resolve(config)?,
        })
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
        Some(Command::Edit(args)) => {
            let options = args.options(&config)?;
            edit::run(&config, &args.lists, options)
        }
        Some(Command::Show(args)) => {
            let view = args.view.resolve(&config)?;
            show::run(&config, &args.lists, scope(args.completed), &view)
        }
        Some(Command::Lsp) => unreachable!("LSP command handled before loading configuration"),
        None => {
            let options = edit::Options {
                view: config.view(None)?,
                ..edit::Options::default()
            };
            edit::run(&config, &[], options)
        }
    }
}
