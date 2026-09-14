use std::{
    collections::{BTreeSet, HashMap},
    path::PathBuf,
    sync::{
        Arc, Weak,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::Duration,
};

use anyhow::{Context, Result, anyhow};
use chrono::Utc;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use tokio::sync::Mutex;
use tower_lsp::{
    Client, LanguageServer, LspService, Server,
    jsonrpc::Result as LspResult,
    lsp_types::{
        ApplyWorkspaceEditResponse, Color, ColorInformation, ColorProviderCapability, Diagnostic,
        DiagnosticSeverity, DidChangeTextDocumentParams, DidCloseTextDocumentParams,
        DidOpenTextDocumentParams, DidSaveTextDocumentParams, DocumentChangeOperation,
        DocumentChanges, DocumentColorParams, InitializeParams, InitializeResult,
        InitializedParams, MessageType, OneOf, OptionalVersionedTextDocumentIdentifier, Position,
        Range, ServerCapabilities, ServerInfo, TextDocumentEdit, TextDocumentSyncCapability,
        TextDocumentSyncKind, TextDocumentSyncOptions, TextEdit, Url, WorkspaceEdit,
    },
};

use crate::{
    edit::{
        hooks::Lifecycle,
        markdown::{self, IdentityManifest},
        planner::{self, Reconciliation},
        session::{self, LoadedLiveSession},
        transaction,
    },
    model::{EditedTaskState, TaskId, TaskState},
    repository::{self, Scope},
};

const DEBOUNCE: Duration = Duration::from_millis(150);
type Documents = Arc<Mutex<HashMap<Url, Arc<Mutex<LiveDocument>>>>>;

pub fn run() -> Result<()> {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .context("failed to start the LSP runtime")?
        .block_on(async {
            let stdin = tokio::io::stdin();
            let stdout = tokio::io::stdout();
            let (service, socket) = LspService::new(Backend::new);
            Server::new(stdin, stdout, socket).serve(service).await;
        });
    Ok(())
}

#[derive(Clone)]
struct Backend {
    client: Client,
    documents: Documents,
    workspace_edits: Arc<AtomicBool>,
}

impl Backend {
    fn new(client: Client) -> Self {
        Self {
            client,
            documents: Arc::new(Mutex::new(HashMap::new())),
            workspace_edits: Arc::new(AtomicBool::new(false)),
        }
    }

    async fn attach(&self, uri: Url, text: String, version: i32) -> Result<()> {
        if !self.workspace_edits.load(Ordering::Relaxed) {
            return Err(anyhow!(
                "editor must support workspace.applyEdit and documentChanges for todomd live mode"
            ));
        }
        let path = uri
            .to_file_path()
            .map_err(|()| anyhow!("todomd live documents must use file URIs"))?;
        let Some(loaded) = session::load_live(&path)? else {
            return Ok(());
        };
        let watcher = source_watcher(
            &uri,
            &loaded,
            Arc::downgrade(&self.documents),
            self.client.clone(),
            Arc::clone(&self.workspace_edits),
        )?;
        let document = Arc::new(Mutex::new(LiveDocument::new(
            text, version, loaded, watcher,
        )));
        self.documents
            .lock()
            .await
            .insert(uri.clone(), Arc::clone(&document));
        let refresh = {
            let mut state = document.lock().await;
            if state.synchronized {
                Ok(())
            } else {
                let accepted = state.accepted_text.clone();
                match self
                    .apply_edit(&uri, state.version, full_range(&state.text), &accepted)
                    .await
                {
                    Ok(()) => {
                        state.text = accepted;
                        state.synchronized = true;
                        Ok(())
                    }
                    Err(error) => Err(error),
                }
            }
        };
        if let Err(error) = refresh {
            self.documents.lock().await.remove(&uri);
            return Err(error);
        }
        session::mark_attached(&document.lock().await.root)?;
        self.validate(&uri).await;
        self.client
            .log_message(MessageType::INFO, "todomd live session attached")
            .await;
        Ok(())
    }

    async fn document(&self, uri: &Url) -> Option<Arc<Mutex<LiveDocument>>> {
        self.documents.lock().await.get(uri).cloned()
    }

    async fn validate(&self, uri: &Url) {
        let Some(document) = self.document(uri).await else {
            return;
        };
        let mut document = document.lock().await;
        document.parse_diagnostic = validate_document(&document)
            .err()
            .map(|error| diagnostic(&error, &document.text, DiagnosticSeverity::ERROR));
        self.client
            .publish_diagnostics(uri.clone(), document.diagnostics(), Some(document.version))
            .await;
    }

    async fn reconcile(&self, uri: &Url, trigger: Trigger) {
        let Some(document) = self.document(uri).await else {
            return;
        };
        let mut state = document.lock().await;
        let mut message = None;

        match reconcile(&mut state, trigger) {
            Ok(Outcome::Quiet) => {}
            Ok(Outcome::Message(kind, text)) => message = Some((kind, text)),
            Ok(Outcome::Edit {
                text,
                version,
                range,
                kind,
                message: text_message,
            }) => match self.apply_edit(uri, version, range, &text).await {
                Ok(()) => {
                    state.text = text;
                    state.synchronized = true;
                    message = Some((kind, text_message));
                }
                Err(error) => {
                    state.synchronized = false;
                    state.state_diagnostic =
                        Some(diagnostic(&error, &state.text, DiagnosticSeverity::ERROR));
                    message = Some((MessageType::ERROR, format!("todomd: {error:#}")));
                }
            },
            Err(error) => {
                state.state_diagnostic =
                    Some(diagnostic(&error, &state.text, DiagnosticSeverity::ERROR));
                message = Some((MessageType::ERROR, format!("todomd: {error:#}")));
            }
        }

        let diagnostics = state.diagnostics();
        let version = Some(state.version);
        drop(state);
        self.client
            .publish_diagnostics(uri.clone(), diagnostics, version)
            .await;
        if let Some((kind, message)) = message {
            self.client.show_message(kind, message).await;
        }
    }

    async fn apply_edit(&self, uri: &Url, version: i32, range: Range, text: &str) -> Result<()> {
        let edit = WorkspaceEdit {
            document_changes: Some(DocumentChanges::Operations(vec![
                DocumentChangeOperation::Edit(TextDocumentEdit {
                    text_document: OptionalVersionedTextDocumentIdentifier {
                        uri: uri.clone(),
                        version: Some(version),
                    },
                    edits: vec![OneOf::Left(TextEdit {
                        range,
                        new_text: text.to_owned(),
                    })],
                }),
            ])),
            ..WorkspaceEdit::default()
        };
        let ApplyWorkspaceEditResponse {
            applied,
            failure_reason,
            ..
        } = self
            .client
            .apply_edit(edit)
            .await
            .context("editor rejected the canonical document update")?;
        if !applied {
            return Err(anyhow!(
                "editor did not apply the canonical document update{}",
                failure_reason.map_or_else(String::new, |reason| format!(": {reason}"))
            ));
        }
        Ok(())
    }
}

#[tower_lsp::async_trait]
impl LanguageServer for Backend {
    async fn initialize(&self, params: InitializeParams) -> LspResult<InitializeResult> {
        let workspace_edits = params
            .capabilities
            .workspace
            .and_then(|workspace| {
                Some(workspace.apply_edit? && workspace.workspace_edit?.document_changes?)
            })
            .unwrap_or(false);
        self.workspace_edits
            .store(workspace_edits, Ordering::Relaxed);
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Options(
                    TextDocumentSyncOptions {
                        open_close: Some(true),
                        change: Some(TextDocumentSyncKind::FULL),
                        save: Some(
                            tower_lsp::lsp_types::TextDocumentSyncSaveOptions::Supported(true),
                        ),
                        ..TextDocumentSyncOptions::default()
                    },
                )),
                color_provider: Some(ColorProviderCapability::Simple(true)),
                ..ServerCapabilities::default()
            },
            server_info: Some(ServerInfo {
                name: "todomd".into(),
                version: Some(env!("CARGO_PKG_VERSION").into()),
            }),
        })
    }

    async fn initialized(&self, _: InitializedParams) {}

    async fn shutdown(&self) -> LspResult<()> {
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let document = params.text_document;
        if let Err(error) = self
            .attach(document.uri, document.text, document.version)
            .await
        {
            self.client
                .show_message(MessageType::ERROR, format!("todomd: {error:#}"))
                .await;
        }
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let uri = params.text_document.uri;
        let Some(document) = self.document(&uri).await else {
            return;
        };
        if let Some(change) = params.content_changes.into_iter().last() {
            let mut document = document.lock().await;
            document.text = change.text;
            document.version = params.text_document.version;
            if document.text == document.accepted_text {
                document.synchronized = true;
            }
        }
        self.validate(&uri).await;
    }

    async fn did_save(&self, params: DidSaveTextDocumentParams) {
        let uri = params.text_document.uri;
        let Some(document) = self.document(&uri).await else {
            return;
        };
        if let Some(text) = params.text {
            let mut document = document.lock().await;
            document.text = text;
            if document.text == document.accepted_text {
                document.synchronized = true;
            }
        }
        self.reconcile(&uri, Trigger::Save).await;
    }

    async fn document_color(
        &self,
        params: DocumentColorParams,
    ) -> LspResult<Vec<ColorInformation>> {
        let Some(document) = self.document(&params.text_document.uri).await else {
            return Ok(Vec::new());
        };
        let (config, lists, text) = {
            let document = document.lock().await;
            (
                document.config.clone(),
                document.lists.clone(),
                document.text.clone(),
            )
        };
        let colors = match repository::list_colors(&config, &lists) {
            Ok(colors) => colors,
            Err(error) => {
                self.client
                    .log_message(
                        MessageType::WARNING,
                        format!("todomd: failed to load list colors: {error:#}"),
                    )
                    .await;
                return Ok(Vec::new());
            }
        };
        Ok(document_colors(&text, &colors))
    }

    async fn did_close(&self, params: DidCloseTextDocumentParams) {
        let uri = params.text_document.uri;
        if let Some(document) = self.documents.lock().await.remove(&uri) {
            let document = document.lock().await;
            match session::close_live(&document.root, &document.accepted_text, &document.text) {
                Ok(true) => {
                    self.client
                        .show_message(
                            MessageType::WARNING,
                            "todomd: unaccepted buffer changes saved as unaccepted.md",
                        )
                        .await;
                }
                Ok(false) => {}
                Err(error) => {
                    self.client
                        .show_message(MessageType::ERROR, format!("todomd: {error:#}"))
                        .await;
                }
            }
        }
        self.client.publish_diagnostics(uri, Vec::new(), None).await;
    }
}

struct LiveDocument {
    text: String,
    accepted_text: String,
    synchronized: bool,
    version: i32,
    root: PathBuf,
    config: crate::config::Config,
    lists: Vec<String>,
    scope: Scope,
    lifecycle: Lifecycle,
    baseline: TaskState,
    recovery_baseline: TaskState,
    manifest: IdentityManifest,
    parse_diagnostic: Option<Diagnostic>,
    state_diagnostic: Option<Diagnostic>,
    _watcher: RecommendedWatcher,
}

impl LiveDocument {
    fn new(
        text: String,
        version: i32,
        loaded: LoadedLiveSession,
        watcher: RecommendedWatcher,
    ) -> Self {
        let lifecycle =
            Lifecycle::live(&loaded.metadata.config.hooks, loaded.metadata.hooks_enabled);
        let synchronized = text == loaded.accepted_text;
        Self {
            accepted_text: loaded.accepted_text,
            text,
            synchronized,
            version,
            root: loaded.root,
            config: loaded.metadata.config,
            lists: loaded.metadata.lists,
            scope: loaded.metadata.scope,
            lifecycle,
            baseline: loaded.baseline,
            recovery_baseline: loaded.recovery_baseline,
            manifest: loaded.manifest,
            parse_diagnostic: None,
            state_diagnostic: None,
            _watcher: watcher,
        }
    }

    fn diagnostics(&self) -> Vec<Diagnostic> {
        self.parse_diagnostic
            .iter()
            .chain(self.state_diagnostic.iter())
            .cloned()
            .collect()
    }
}

#[derive(Clone, Copy)]
enum Trigger {
    Save,
    Source,
}

enum Outcome {
    Quiet,
    Message(MessageType, String),
    Edit {
        text: String,
        version: i32,
        range: Range,
        kind: MessageType,
        message: String,
    },
}

fn validate_document(document: &LiveDocument) -> Result<()> {
    let edited = markdown::parse(&document.text, &document.baseline, &document.manifest)?;
    let missing = identities_outside(&edited, &document.baseline);
    let mut baseline = document.baseline.clone();
    add_tasks(&mut baseline, &document.recovery_baseline, &missing);
    planner::reconcile(&baseline, &edited, &baseline)?;
    Ok(())
}

fn reconcile(document: &mut LiveDocument, trigger: Trigger) -> Result<Outcome> {
    if !document.synchronized {
        return Err(anyhow!(
            "live document is out of sync; reload the accepted session document before saving"
        ));
    }
    let edited = markdown::parse(&document.text, &document.baseline, &document.manifest)?;
    let (current, sources) =
        repository::load_lists(&document.config, &document.lists, document.scope)?;
    let missing = identities_outside(&edited, &document.baseline);
    let (reconciliation_baseline, reconciliation_current, sources) = if missing.is_empty() {
        (document.baseline.clone(), current.clone(), sources)
    } else {
        let (current_all, sources) =
            repository::load_lists(&document.config, &document.lists, Scope::All)?;
        let mut baseline = document.baseline.clone();
        let mut current = current.clone();
        add_tasks(&mut baseline, &document.recovery_baseline, &missing);
        add_tasks(&mut current, &current_all, &missing);
        (baseline, current, sources)
    };
    let reconciliation =
        planner::reconcile(&reconciliation_baseline, &edited, &reconciliation_current)?;

    document.parse_diagnostic = None;
    match reconciliation {
        Reconciliation::NoChange => {
            document.state_diagnostic = None;
            Ok(Outcome::Quiet)
        }
        Reconciliation::Inbound => accept_inbound(document, current),
        Reconciliation::Outgoing(_) if matches!(trigger, Trigger::Source) => Ok(Outcome::Quiet),
        Reconciliation::Outgoing(plan) => {
            let staged = transaction::stage(&plan, &sources, &document.root, Utc::now())?;
            transaction::apply(&staged, &sources)?;
            let (accepted, accepted_sources) =
                repository::load_lists(&document.config, &document.lists, document.scope).context(
                    "source changes were applied, but the accepted state could not be read",
                )?;
            transaction::verify_applied(&staged, &sources, &accepted_sources).context(
                "source changes were applied, but concurrent changes prevented acceptance",
            )?;
            let recovery = load_recovery_baseline(document)
                .context("source changes were applied, but the recovery state could not be read")?;
            let mut manifest = document.manifest.clone();
            let text = markdown::render(&accepted, &mut manifest).context(
                "source changes were applied, but the accepted state could not be rendered",
            )?;
            session::accept_live(&document.root, &text, &manifest, &accepted, &recovery)
                .context("source changes were applied, but the live session was not refreshed")?;
            let range = full_range(&document.text);
            document.baseline = accepted;
            document.recovery_baseline = recovery;
            document.manifest = manifest;
            document.accepted_text = text.clone();
            document.state_diagnostic = None;
            let hook = document.lifecycle.after_apply();
            let (kind, message) = match hook {
                Ok(()) => (MessageType::INFO, "todomd: changes applied".to_owned()),
                Err(error) => (
                    MessageType::ERROR,
                    format!("todomd: changes applied; {error:#}"),
                ),
            };
            Ok(Outcome::Edit {
                text,
                version: document.version,
                range,
                kind,
                message,
            })
        }
        Reconciliation::Conflict => {
            let message = "todomd: Markdown and source lists both changed".to_owned();
            document.state_diagnostic = Some(diagnostic(
                &anyhow!(message.clone()),
                &document.text,
                DiagnosticSeverity::ERROR,
            ));
            Ok(Outcome::Message(MessageType::WARNING, message))
        }
    }
}

fn accept_inbound(document: &mut LiveDocument, current: TaskState) -> Result<Outcome> {
    let recovery = load_recovery_baseline(document)?;
    let mut manifest = document.manifest.clone();
    let text = markdown::render(&current, &mut manifest)
        .context("failed to render an inbound source change")?;
    session::accept_live(&document.root, &text, &manifest, &current, &recovery)
        .context("failed to accept an inbound source change")?;
    let range = full_range(&document.text);
    document.baseline = current;
    document.recovery_baseline = recovery;
    document.manifest = manifest;
    document.accepted_text = text.clone();
    document.state_diagnostic = None;
    Ok(Outcome::Edit {
        text,
        version: document.version,
        range,
        kind: MessageType::INFO,
        message: "todomd: source changes loaded".into(),
    })
}

fn load_recovery_baseline(document: &LiveDocument) -> Result<TaskState> {
    if document.scope == Scope::All {
        return Ok(repository::load_lists(&document.config, &document.lists, Scope::All)?.0);
    }
    Ok(repository::load_lists(&document.config, &document.lists, Scope::All)?.0)
}

fn source_watcher(
    uri: &Url,
    loaded: &LoadedLiveSession,
    documents: Weak<Mutex<HashMap<Url, Arc<Mutex<LiveDocument>>>>>,
    client: Client,
    workspace_edits: Arc<AtomicBool>,
) -> Result<RecommendedWatcher> {
    let uri = uri.clone();
    let runtime = tokio::runtime::Handle::current();
    let callback_uri = uri.clone();
    let generation = Arc::new(AtomicU64::new(0));
    let mut watcher =
        notify::recommended_watcher(move |event: notify::Result<Event>| match event {
            Ok(event) if is_content_event(&event.kind) => {
                let documents = documents.clone();
                let client = client.clone();
                let uri = callback_uri.clone();
                let workspace_edits = Arc::clone(&workspace_edits);
                let generation = Arc::clone(&generation);
                let event_generation = generation.fetch_add(1, Ordering::Relaxed) + 1;
                runtime.spawn(async move {
                    tokio::time::sleep(DEBOUNCE).await;
                    if generation.load(Ordering::Relaxed) != event_generation {
                        return;
                    }
                    let Some(documents) = documents.upgrade() else {
                        return;
                    };
                    let backend = Backend {
                        client,
                        documents,
                        workspace_edits,
                    };
                    backend.reconcile(&uri, Trigger::Source).await;
                });
            }
            Ok(_) => {}
            Err(error) => {
                let client = client.clone();
                runtime.spawn(async move {
                    client
                        .show_message(
                            MessageType::ERROR,
                            format!("todomd: filesystem watcher failed: {error}"),
                        )
                        .await;
                });
            }
        })
        .context("failed to create source-list watcher")?;

    let (_, sources) = repository::load_lists(
        &loaded.metadata.config,
        &loaded.metadata.lists,
        loaded.metadata.scope,
    )?;
    for directory in sources.list_dirs.values() {
        watcher
            .watch(directory, RecursiveMode::NonRecursive)
            .with_context(|| format!("failed to watch {}", directory.display()))?;
    }
    Ok(watcher)
}

fn is_content_event(kind: &EventKind) -> bool {
    matches!(
        kind,
        EventKind::Any | EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
    )
}

fn identities_outside(edited: &EditedTaskState, baseline: &TaskState) -> BTreeSet<TaskId> {
    let baseline_ids = baseline
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .map(|task| &task.id)
        .collect::<BTreeSet<_>>();
    edited
        .lists
        .iter()
        .flat_map(|list| &list.tasks)
        .filter_map(|task| task.id.as_ref())
        .filter(|id| !baseline_ids.contains(id))
        .cloned()
        .collect()
}

fn add_tasks(target: &mut TaskState, source: &TaskState, ids: &BTreeSet<TaskId>) {
    for source_list in &source.lists {
        let Some(target_list) = target
            .lists
            .iter_mut()
            .find(|list| list.name == source_list.name)
        else {
            continue;
        };
        for task in &source_list.tasks {
            if ids.contains(&task.id) && !target_list.tasks.iter().any(|item| item.id == task.id) {
                target_list.tasks.push(task.clone());
            }
        }
    }
}

fn document_colors(
    text: &str,
    colors: &std::collections::BTreeMap<String, repository::ListColor>,
) -> Vec<ColorInformation> {
    text.lines()
        .enumerate()
        .filter_map(|(line, text)| {
            let name = text.strip_prefix("# ")?;
            let color = colors.get(name)?;
            Some(ColorInformation {
                range: Range::new(
                    Position::new(line as u32, 2),
                    Position::new(line as u32, utf16_len(text) as u32),
                ),
                color: Color {
                    red: f32::from(color.red) / 255.0,
                    green: f32::from(color.green) / 255.0,
                    blue: f32::from(color.blue) / 255.0,
                    alpha: 1.0,
                },
            })
        })
        .collect()
}

fn diagnostic(error: &anyhow::Error, text: &str, severity: DiagnosticSeverity) -> Diagnostic {
    let message = format!("{error:#}");
    let line = error_line(&message)
        .unwrap_or(1)
        .saturating_sub(1)
        .min(text.lines().count().saturating_sub(1));
    let end = text.lines().nth(line).map(utf16_len).unwrap_or(0);
    Diagnostic {
        range: Range::new(
            Position::new(line as u32, 0),
            Position::new(line as u32, end as u32),
        ),
        severity: Some(severity),
        source: Some("todomd".into()),
        message,
        ..Diagnostic::default()
    }
}

fn error_line(message: &str) -> Option<usize> {
    let (_, suffix) = message.split_once("line ")?;
    let digits = suffix
        .chars()
        .take_while(char::is_ascii_digit)
        .collect::<String>();
    digits.parse().ok()
}

fn full_range(text: &str) -> Range {
    let mut lines = text.split('\n');
    let mut line = 0_u32;
    let mut character = 0_u32;
    if let Some(first) = lines.next() {
        character = utf16_len(first) as u32;
    }
    for value in lines {
        line += 1;
        character = utf16_len(value) as u32;
    }
    Range::new(Position::new(0, 0), Position::new(line, character))
}

fn utf16_len(value: &str) -> usize {
    value.encode_utf16().count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diagnostics_use_reported_line_and_utf16_columns() {
        let text = "# Personal\n\n😀 broken\n";
        let diagnostic = diagnostic(
            &anyhow!("line 3: expected a task"),
            text,
            DiagnosticSeverity::ERROR,
        );

        assert_eq!(diagnostic.range.start, Position::new(2, 0));
        assert_eq!(diagnostic.range.end, Position::new(2, 9));
    }

    #[test]
    fn whole_document_ranges_include_a_final_empty_line() {
        assert_eq!(
            full_range("# Personal\n"),
            Range::new(Position::new(0, 0), Position::new(1, 0))
        );
    }

    #[test]
    fn document_colors_cover_known_heading_names() {
        let colors = std::collections::BTreeMap::from([
            (
                "Pós-graduação".to_owned(),
                repository::ListColor {
                    red: 0x33,
                    green: 0x66,
                    blue: 0x99,
                },
            ),
            (
                "Personal".to_owned(),
                repository::ListColor {
                    red: 0xff,
                    green: 0,
                    blue: 0,
                },
            ),
        ]);

        let information = document_colors("# Pós-graduação\n\n- [ ] Task\n\n# Unknown\n", &colors);

        assert_eq!(information.len(), 1);
        assert_eq!(
            information[0].range,
            Range::new(Position::new(0, 2), Position::new(0, 15))
        );
        assert_eq!(information[0].color.red, 0x33 as f32 / 255.0);
        assert_eq!(information[0].color.green, 0x66 as f32 / 255.0);
        assert_eq!(information[0].color.blue, 0x99 as f32 / 255.0);
        assert_eq!(information[0].color.alpha, 1.0);
    }
}
