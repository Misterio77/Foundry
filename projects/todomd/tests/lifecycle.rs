#![cfg(unix)]

use std::{
    fs,
    io::{BufRead, BufReader, Read, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{ChildStdin, ChildStdout, Command, Output, Stdio},
};

use serde_json::{Value, json};
use tempfile::TempDir;
use todomd::{
    config::Config,
    edit::{
        self,
        session::{LiveMetadata, Session},
    },
    repository::{self, Scope},
};

struct Case {
    _root: TempDir,
    calendars: PathBuf,
    config: PathBuf,
    hook_log: PathBuf,
    runtime: PathBuf,
}

impl Case {
    fn new(after_apply_status: i32) -> Self {
        let root = tempfile::tempdir().unwrap();
        let calendars = root.path().join("calendars");
        copy_tree(&fixture_root(), &calendars);
        let runtime = root.path().join("runtime");
        fs::create_dir(&runtime).unwrap();
        let hook_log = root.path().join("hooks.log");
        let hook = root.path().join("hook");
        write_executable(
            &hook,
            "#!/bin/sh\nprintf 'apply\\n' >> \"$1\"\nexit \"$2\"\n",
        );
        let config = root.path().join("config.toml");
        fs::write(
            &config,
            format!(
                "calendar_roots = [{calendars:?}]\n\
                 [hooks]\n\
                 after_apply = [\"sh\", {hook:?}, {log:?}, \"{after_apply_status}\"]\n",
                calendars = calendars.to_string_lossy(),
                hook = hook.to_string_lossy(),
                log = hook_log.to_string_lossy(),
            ),
        )
        .unwrap();

        Self {
            _root: root,
            calendars,
            config,
            hook_log,
            runtime,
        }
    }

    fn base(&self, editor: &str) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_todomd"));
        command
            .args(["--config", self.config.to_str().unwrap()])
            .env("VISUAL", editor)
            .env_remove("EDITOR")
            .env("XDG_RUNTIME_DIR", &self.runtime);
        command
    }

    fn edit_command(&self, editor: &str) -> Command {
        let mut command = self.base(editor);
        command.args(["edit", "Postgrad", "Personal"]);
        command
    }

    fn hooks(&self) -> String {
        fs::read_to_string(&self.hook_log).unwrap()
    }
}

#[test]
fn generates_completions_without_loading_configuration() {
    let output = Command::new(env!("CARGO_BIN_EXE_todomd"))
        .args([
            "--config",
            "/definitely/missing",
            "--generate-completion",
            "fish",
        ])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    let completion = String::from_utf8(output.stdout).unwrap();
    assert!(completion.contains("complete -c todomd"));
    assert!(completion.contains("-a \"edit\""));
    assert!(completion.contains("-l completed"));
    assert!(!completion.contains("-l watch"));
}

#[test]
fn show_prints_every_list_as_json_without_hooks_or_a_terminal() {
    let case = Case::new(0);
    let output = case.base("false").arg("show").output().unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    assert!(!case.hook_log.exists());

    let tasks: Value = serde_json::from_slice(&output.stdout).unwrap();
    let tasks = tasks.as_array().unwrap();
    assert_eq!(tasks.len(), 2);
    assert_eq!(tasks[0]["list"], "Personal");
    assert_eq!(tasks[0]["summary"], "Buy milk, bread");
    assert_eq!(
        tasks[0]["file"],
        case.calendars
            .join("Personal/groceries.ics")
            .to_str()
            .unwrap()
    );
    assert_eq!(tasks[1]["uid"], "write@example.test");
}

#[test]
fn show_reports_unrepresentable_tasks_without_breaking_json() {
    let case = Case::new(0);
    let output = case
        .base("false")
        .args(["show", "Postgrad"])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("1 task without a summary not shown"));
    assert!(stderr.contains("nosummary.ics"));
    let tasks: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(tasks.as_array().unwrap().len(), 1);
}

#[test]
fn show_completed_and_selected_lists_work() {
    let case = Case::new(0);
    let output = case
        .base("false")
        .args(["show", "--completed", "Postgrad"])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    let tasks: Value = serde_json::from_slice(&output.stdout).unwrap();
    let tasks = tasks.as_array().unwrap();
    assert_eq!(tasks.len(), 2);
    assert!(
        tasks
            .iter()
            .any(|task| task["uid"] == "read@example.test" && task["completed"] == true)
    );
    assert!(tasks.iter().all(|task| task["list"] == "Postgrad"));
}

#[test]
fn a_list_name_is_not_mistaken_for_a_subcommand() {
    let case = Case::new(0);
    let output = case.base("true").arg("Postgrad").output().unwrap();

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unrecognized subcommand"));
}

#[test]
fn edit_requires_an_attached_language_server() {
    let case = Case::new(0);
    let output = case.edit_command("true").output().unwrap();
    let text = output_text(&output);

    assert!(!output.status.success());
    assert!(!case.hook_log.exists());
    assert!(text.contains("editor closed before todomd lsp attached"));
    assert!(text.contains("live session retained at"));
}

#[test]
fn lsp_applies_saves_and_loads_source_changes() {
    let case = Case::new(0);
    let config = Config::load(Some(&case.config)).unwrap();
    let lists = vec!["Postgrad".to_owned(), "Personal".to_owned()];
    let rendered = edit::render_lists(&config, &lists, Scope::Active).unwrap();
    let recovery = repository::load_lists(&config, &lists, Scope::All)
        .unwrap()
        .0;
    let metadata = LiveMetadata {
        config,
        lists,
        scope: Scope::Active,
        hooks_enabled: true,
    };
    let session = Session::create_live(&rendered, &metadata, &recovery).unwrap();
    let uri = format!("file://{}", session.tasks_path().display());
    let edited = rendered.markdown.replace("Write paper draft", "LSP paper");

    let mut child = Command::new(env!("CARGO_BIN_EXE_todomd"))
        .arg("lsp")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut peer = LspPeer {
        stdin: child.stdin.take().unwrap(),
        stdout: BufReader::new(child.stdout.take().unwrap()),
    };
    peer.send(json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {"capabilities": {"workspace": {
            "applyEdit": true,
            "workspaceEdit": {"documentChanges": true}
        }}}
    }));
    assert_eq!(peer.read()["id"], 1);
    peer.send(json!({"jsonrpc": "2.0", "method": "initialized", "params": {}}));
    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {"textDocument": {
            "uri": uri,
            "languageId": "markdown",
            "version": 1,
            "text": rendered.markdown
        }}
    }));
    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 2},
            "contentChanges": [{"text": edited}]
        }
    }));
    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didSave",
        "params": {"textDocument": {"uri": uri}}
    }));

    let canonical = receive_workspace_edit(&mut peer, "LSP paper");
    assert!(canonical.contains("<!--t"));
    assert!(session.is_attached());
    assert_eq!(case.hooks(), "apply\n");
    let source_path = case.calendars.join("Postgrad/write.ics");
    let source = fs::read_to_string(&source_path).unwrap();
    assert!(source.contains("SUMMARY:LSP paper"));

    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 3},
            "contentChanges": [{"text": canonical}]
        }
    }));
    fs::write(
        &source_path,
        source.replace("SUMMARY:LSP paper", "SUMMARY:Changed externally"),
    )
    .unwrap();
    receive_workspace_edit(&mut peer, "Changed externally");

    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didClose",
        "params": {"textDocument": {"uri": uri}}
    }));
    peer.send(json!({"jsonrpc": "2.0", "id": 99, "method": "shutdown"}));
    while peer.read()["id"] != 99 {}
    peer.send(json!({"jsonrpc": "2.0", "method": "exit"}));
    drop(peer);
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success(), "{}", output_text(&output));
}

fn receive_workspace_edit(peer: &mut LspPeer, expected: &str) -> String {
    for _ in 0..12 {
        let message = peer.read();
        if message["method"] != "workspace/applyEdit" {
            continue;
        }
        let new_text = message["params"]["edit"]["documentChanges"][0]["edits"][0]["newText"]
            .as_str()
            .unwrap()
            .to_owned();
        assert!(new_text.contains(expected));
        peer.send(json!({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {"applied": true}
        }));
        return new_text;
    }
    panic!("server did not send a workspace edit");
}

struct LspPeer {
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl LspPeer {
    fn send(&mut self, message: Value) {
        let body = serde_json::to_vec(&message).unwrap();
        write!(self.stdin, "Content-Length: {}\r\n\r\n", body.len()).unwrap();
        self.stdin.write_all(&body).unwrap();
        self.stdin.flush().unwrap();
    }

    fn read(&mut self) -> Value {
        let mut content_length = None;
        loop {
            let mut line = String::new();
            self.stdout.read_line(&mut line).unwrap();
            assert!(!line.is_empty(), "LSP server closed its output");
            if line == "\r\n" {
                break;
            }
            if let Some(value) = line.strip_prefix("Content-Length: ") {
                content_length = Some(value.trim().parse::<usize>().unwrap());
            }
        }
        let mut body = vec![0; content_length.expect("LSP message has a content length")];
        self.stdout.read_exact(&mut body).unwrap();
        serde_json::from_slice(&body).unwrap()
    }
}

fn fixture_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/calendars")
}

fn copy_tree(source: &Path, destination: &Path) {
    fs::create_dir(destination).unwrap();
    for entry in fs::read_dir(source).unwrap() {
        let entry = entry.unwrap();
        let destination = destination.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &destination);
        } else {
            fs::copy(entry.path(), destination).unwrap();
        }
    }
}

fn write_executable(path: &Path, contents: &str) {
    fs::write(path, contents).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
}

fn output_text(output: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}
