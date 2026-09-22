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
    Edit(SessionSelectionArgs),
    /// Print tasks and their source files as JSON.
    Show(ShowArgs),
    /// Create, apply, or close an editor-independent session.
    Session {
        #[command(subcommand)]
        command: SessionCommand,
    },
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
struct ShowArgs {
    /// Include completed and cancelled tasks.
    #[arg(long)]
    completed: bool,

    #[command(flatten)]
    view: ViewArgs,

    /// Whole VTODO lists to print, in order [default: every list].
    lists: Vec<String>,
}

#[derive(Debug, Subcommand)]
enum SessionCommand {
    /// Create a reusable session and print its directory.
    Create(SessionSelectionArgs),
    /// Apply the current tasks.md and keep the session open.
    Apply(SessionPathArgs),
    /// Remove a clean session.
    Close(SessionCloseArgs),
}

#[derive(Args, Debug)]
struct SessionSelectionArgs {
    /// Disable the configured after_apply hook for this session.
    #[arg(long)]
    no_hooks: bool,

    /// Include completed and cancelled tasks.
    #[arg(long)]
    completed: bool,

    #[command(flatten)]
    view: ViewArgs,

    /// Whole VTODO lists to include, in document order [default: every list].
    lists: Vec<String>,
}

#[derive(Args, Debug)]
struct SessionPathArgs {
    /// Session directory created by `todomd session create`.
    session: PathBuf,
}

#[derive(Args, Debug)]
struct SessionCloseArgs {
    /// Discard unapplied changes.
    #[arg(long)]
    force: bool,

    /// Session directory created by `todomd session create`.
    session: PathBuf,
}

impl SessionSelectionArgs {
    fn options(&self, config: &Config) -> Result<edit::SessionOptions> {
        Ok(edit::SessionOptions {
            hooks_enabled: !self.no_hooks,
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
    match cli.command {
        Some(Command::Lsp) => lsp::run(),
        Some(Command::Session {
            command: SessionCommand::Apply(args),
        }) => {
            let outcome = edit::session_commands::apply(&args.session)?;
            eprintln!("{}", outcome.message());
            Ok(())
        }
        Some(Command::Session {
            command: SessionCommand::Close(args),
        }) => edit::session_commands::close(&args.session, args.force),
        command => {
            let config = Config::load(cli.config.as_deref())?;
            run_with_config(config, command)
        }
    }
}

fn run_with_config(config: Config, command: Option<Command>) -> Result<()> {
    match command {
        Some(Command::Edit(args)) => {
            let options = args.options(&config)?;
            edit::run(&config, &args.lists, options)
        }
        Some(Command::Show(args)) => {
            let view = args.view.resolve(&config)?;
            show::run(&config, &args.lists, scope(args.completed), &view)
        }
        Some(Command::Session {
            command: SessionCommand::Create(args),
        }) => {
            let options = args.options(&config)?;
            let path = edit::session_commands::create(&config, &args.lists, options)?;
            println!("{}", path.display());
            Ok(())
        }
        Some(Command::Session { .. } | Command::Lsp) => {
            unreachable!("command handled before loading configuration")
        }
        None => {
            let options = edit::SessionOptions {
                view: config.view(None)?,
                ..edit::SessionOptions::default()
            };
            edit::run(&config, &[], options)
        }
    }
}
