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
        session::{self, LIVE_FORMAT_VERSION, LiveMetadata, Session},
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
                 [views.flat]\n\
                 group_by = []\n\
                 sort_by = [\"due\", \"summary\"]\n\
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
    assert!(completion.contains("-a \"session\""));
    assert!(completion.contains("-a \"apply\""));
    assert!(completion.contains("-l completed"));
    assert!(completion.contains("-l view"));
    assert!(completion.contains("-l group-by"));
    assert!(completion.contains("-l sort-by"));
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
fn show_view_selection_and_overrides_work() {
    let case = Case::new(0);
    let output = case
        .base("false")
        .args(["show", "--view", "flat"])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    let tasks: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(tasks[0]["uid"], "write@example.test");
    assert_eq!(tasks[1]["uid"], "groceries@example.test");

    let duplicate = case
        .base("false")
        .args(["show", "--group-by", "list,list"])
        .output()
        .unwrap();
    assert!(!duplicate.status.success());
    assert!(output_text(&duplicate).contains("must not contain duplicate keys"));
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
fn explicit_session_create_apply_and_close_work_without_an_editor() {
    let case = Case::new(0);
    let created = case
        .base("false")
        .args(["session", "create", "Postgrad", "Personal"])
        .output()
        .unwrap();
    assert!(created.status.success(), "{}", output_text(&created));
    let session = PathBuf::from(String::from_utf8(created.stdout).unwrap().trim());
    assert!(session.join("tasks.md").is_file());
    assert!(session.join("accepted.md").is_file());

    let tasks = fs::read_to_string(session.join("tasks.md")).unwrap();
    fs::write(
        session.join("tasks.md"),
        tasks.replace("Write paper draft", "Applied manually"),
    )
    .unwrap();
    let applied = Command::new(env!("CARGO_BIN_EXE_todomd"))
        .args([
            "--config",
            "/definitely/missing",
            "session",
            "apply",
            session.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(applied.status.success(), "{}", output_text(&applied));
    assert!(String::from_utf8_lossy(&applied.stderr).contains("1 updated"));
    assert_eq!(case.hooks(), "apply\n");
    assert!(
        fs::read_to_string(case.calendars.join("Postgrad/write.ics"))
            .unwrap()
            .contains("SUMMARY:Applied manually")
    );
    assert_eq!(
        fs::read(session.join("tasks.md")).unwrap(),
        fs::read(session.join("accepted.md")).unwrap()
    );

    let closed = case
        .base("false")
        .args(["session", "close", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(closed.status.success(), "{}", output_text(&closed));
    assert!(!session.exists());
}

#[test]
fn explicit_session_close_protects_unapplied_changes() {
    let case = Case::new(0);
    let fake = case.runtime.join("session-unrelated");
    fs::create_dir(&fake).unwrap();
    let rejected = case
        .base("false")
        .args(["session", "close", "--force", fake.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!rejected.status.success());
    assert!(output_text(&rejected).contains("is not a todomd session"));
    assert!(fake.is_dir());

    let created = case
        .base("false")
        .args(["session", "create", "Personal"])
        .output()
        .unwrap();
    assert!(created.status.success(), "{}", output_text(&created));
    let session = PathBuf::from(String::from_utf8(created.stdout).unwrap().trim());
    fs::write(session.join("tasks.md"), "unapplied\n").unwrap();

    let lock = session::lock(&session).unwrap();
    let in_use = case
        .base("false")
        .args(["session", "close", "--force", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!in_use.status.success());
    assert!(output_text(&in_use).contains("already in use"));
    assert!(session.is_dir());
    drop(lock);

    let refused = case
        .base("false")
        .args(["session", "close", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!refused.status.success());
    assert!(output_text(&refused).contains("session has unapplied changes"));
    assert!(session.is_dir());

    let forced = case
        .base("false")
        .args(["session", "close", "--force", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(forced.status.success(), "{}", output_text(&forced));
    assert!(!session.exists());
}

#[test]
fn explicit_session_can_create_and_delete_a_task() {
    let case = Case::new(0);
    let created = case
        .base("false")
        .args(["session", "create", "Personal"])
        .output()
        .unwrap();
    assert!(created.status.success(), "{}", output_text(&created));
    let session = PathBuf::from(String::from_utf8(created.stdout).unwrap().trim());
    let tasks_path = session.join("tasks.md");
    let mut tasks = fs::read_to_string(&tasks_path).unwrap();
    tasks.push_str("- [ ] Created manually\n");
    fs::write(&tasks_path, tasks).unwrap();

    let applied = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(applied.status.success(), "{}", output_text(&applied));
    assert!(output_text(&applied).contains("1 created"));
    let canonical = fs::read_to_string(&tasks_path).unwrap();
    let created_line = canonical
        .lines()
        .find(|line| line.contains("Created manually"))
        .unwrap();
    assert!(created_line.contains("<!--t"));
    let created_source = fs::read_dir(case.calendars.join("Personal"))
        .unwrap()
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .find(|path| {
            path.extension().is_some_and(|extension| extension == "ics")
                && fs::read_to_string(path)
                    .is_ok_and(|contents| contents.contains("SUMMARY:Created manually"))
        })
        .unwrap();

    let retained = canonical
        .lines()
        .filter(|line| !line.contains("Created manually"))
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";
    fs::write(&tasks_path, retained).unwrap();
    let deleted = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(deleted.status.success(), "{}", output_text(&deleted));
    assert!(output_text(&deleted).contains("1 deleted"));
    assert!(!created_source.exists());
    assert_eq!(case.hooks(), "apply\napply\n");
}

#[test]
fn explicit_session_can_reopen_a_task_completed_in_active_scope() {
    let case = Case::new(0);
    let created = case
        .base("false")
        .args(["session", "create", "Postgrad"])
        .output()
        .unwrap();
    assert!(created.status.success(), "{}", output_text(&created));
    let session = PathBuf::from(String::from_utf8(created.stdout).unwrap().trim());
    let tasks_path = session.join("tasks.md");
    let tasks = fs::read_to_string(&tasks_path).unwrap();
    fs::write(
        &tasks_path,
        tasks.replace("- [ ] -2026-09-10", "- [x] -2026-09-10"),
    )
    .unwrap();

    let completed = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(completed.status.success(), "{}", output_text(&completed));
    let tasks = fs::read_to_string(&tasks_path).unwrap();
    assert!(tasks.contains("- [x] -2026-09-10"));
    fs::write(
        &tasks_path,
        tasks.replace("- [x] -2026-09-10", "- [ ] -2026-09-10"),
    )
    .unwrap();

    let reopened = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(reopened.status.success(), "{}", output_text(&reopened));
    assert!(
        !fs::read_to_string(case.calendars.join("Postgrad/write.ics"))
            .unwrap()
            .contains("STATUS:COMPLETED")
    );
    assert_eq!(case.hooks(), "apply\napply\n");
}

#[test]
fn explicit_session_apply_accepts_inbound_and_canonicalizes_noop_edits() {
    let case = Case::new(0);
    let created = case
        .base("false")
        .args(["session", "create", "Personal"])
        .output()
        .unwrap();
    assert!(created.status.success(), "{}", output_text(&created));
    let session = PathBuf::from(String::from_utf8(created.stdout).unwrap().trim());
    let source_path = case.calendars.join("Personal/groceries.ics");
    let source = fs::read_to_string(&source_path).unwrap();
    fs::write(
        &source_path,
        source.replace("SUMMARY:Buy milk\\, bread", "SUMMARY:Changed externally"),
    )
    .unwrap();

    let inbound = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(inbound.status.success(), "{}", output_text(&inbound));
    assert!(output_text(&inbound).contains("source changes loaded"));
    assert!(
        fs::read_to_string(session.join("tasks.md"))
            .unwrap()
            .contains("Changed externally")
    );
    assert!(!case.hook_log.exists());

    let tasks_path = session.join("tasks.md");
    let tasks = fs::read_to_string(&tasks_path).unwrap();
    fs::write(
        &tasks_path,
        tasks.replace(
            "- [ ] Changed externally",
            "- [ ] @Personal Changed externally",
        ),
    )
    .unwrap();
    let noop = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(noop.status.success(), "{}", output_text(&noop));
    assert!(output_text(&noop).contains("no changes"));
    assert!(
        !fs::read_to_string(&tasks_path)
            .unwrap()
            .contains("@Personal")
    );
    assert_eq!(
        fs::read(&tasks_path).unwrap(),
        fs::read(session.join("accepted.md")).unwrap()
    );
    assert!(!case.hook_log.exists());
}

#[test]
fn explicit_session_apply_preserves_conflicts() {
    let case = Case::new(0);
    let created = case
        .base("false")
        .args(["session", "create", "Postgrad"])
        .output()
        .unwrap();
    assert!(created.status.success(), "{}", output_text(&created));
    let session = PathBuf::from(String::from_utf8(created.stdout).unwrap().trim());
    let tasks_path = session.join("tasks.md");
    let tasks = fs::read_to_string(&tasks_path).unwrap();
    fs::write(
        &tasks_path,
        tasks.replace("Write paper draft", "Changed in Markdown"),
    )
    .unwrap();
    let source_path = case.calendars.join("Postgrad/write.ics");
    let source = fs::read_to_string(&source_path).unwrap();
    fs::write(
        &source_path,
        source.replace("SUMMARY:Write paper draft", "SUMMARY:Changed in ICS"),
    )
    .unwrap();

    let applied = case
        .base("false")
        .args(["session", "apply", session.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!applied.status.success());
    assert!(output_text(&applied).contains("both changed"));
    assert!(session.is_dir());
    assert!(
        fs::read_to_string(tasks_path)
            .unwrap()
            .contains("Changed in Markdown")
    );
    assert!(
        fs::read_to_string(source_path)
            .unwrap()
            .contains("SUMMARY:Changed in ICS")
    );
    assert!(!case.hook_log.exists());
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
    fs::write(case.calendars.join("Postgrad/color"), "#336699\n").unwrap();
    let config = Config::load(Some(&case.config)).unwrap();
    let lists = vec!["Postgrad".to_owned(), "Personal".to_owned()];
    let rendered = edit::render_lists(&config, &lists, Scope::Active).unwrap();
    let recovery = repository::load_lists(&config, &lists, Scope::All)
        .unwrap()
        .0;
    let metadata = LiveMetadata {
        format_version: LIVE_FORMAT_VERSION,
        view: config.view(None).unwrap(),
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
        "params": {"capabilities": {
            "workspace": {
                "applyEdit": true,
                "workspaceEdit": {"documentChanges": true}
            },
            "window": {"workDoneProgress": true}
        }}
    }));
    let initialize = peer.read();
    assert_eq!(initialize["id"], 1);
    assert_eq!(initialize["result"]["capabilities"]["colorProvider"], true);
    assert_eq!(
        initialize["result"]["capabilities"]["executeCommandProvider"]["commands"],
        json!(["todomd.changeView"])
    );
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
        "id": 2,
        "method": "textDocument/documentColor",
        "params": {"textDocument": {"uri": uri}}
    }));
    let colors = read_response(&mut peer, 2);
    assert_eq!(colors["result"].as_array().unwrap().len(), 1);
    assert_eq!(
        colors["result"][0]["range"]["start"],
        json!({"line": 0, "character": 2})
    );
    assert_eq!(
        colors["result"][0]["range"]["end"],
        json!({"line": 0, "character": 10})
    );
    let color = &colors["result"][0]["color"];
    assert!((color["red"].as_f64().unwrap() - 0.2).abs() < 1e-6);
    assert!((color["green"].as_f64().unwrap() - 0.4).abs() < 1e-6);
    assert!((color["blue"].as_f64().unwrap() - 0.6).abs() < 1e-6);
    assert_eq!(color["alpha"], 1.0);

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

    let (canonical, events) = receive_workspace_edit(&mut peer, "LSP paper");
    assert_hook_follows_workspace_edit(&mut peer, &events);
    assert!(canonical.contains("<!--t"));
    assert!(session.is_attached());
    assert_eq!(case.hooks(), "apply\n");
    let source_path = case.calendars.join("Postgrad/write.ics");
    let source = fs::read_to_string(&source_path).unwrap();
    assert!(source.contains("SUMMARY:LSP paper"));

    let completed = canonical.replace("- [ ] -2026-09-10 LSP paper", "- [x] -2026-09-10 LSP paper");
    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 3},
            "contentChanges": [{"text": completed}]
        }
    }));
    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didSave",
        "params": {"textDocument": {"uri": uri}}
    }));
    let (canonical, events) = receive_workspace_edit(&mut peer, "LSP paper");
    assert_hook_follows_workspace_edit(&mut peer, &events);
    assert!(canonical.contains("- [x] -2026-09-10 LSP paper"));
    assert!(
        fs::read_to_string(&source_path)
            .unwrap()
            .contains("STATUS:COMPLETED")
    );

    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 4},
            "contentChanges": [{"text": canonical}]
        }
    }));
    let source = fs::read_to_string(&source_path).unwrap();
    fs::write(
        &source_path,
        source.replace("SUMMARY:LSP paper", "SUMMARY:Changed externally"),
    )
    .unwrap();
    let (canonical, progress) = receive_workspace_edit(&mut peer, "Changed externally");
    let (token, message) = receive_progress_end(&mut peer);
    assert_eq!(message.as_deref(), Some("ICS changes loaded"));
    assert!(progress.iter().any(|progress| {
        progress["params"]["token"] == token
            && progress["params"]["value"]["kind"] == "begin"
            && progress["params"]["value"]["message"] == "Updating Markdown from ICS"
    }));
    assert!(canonical.contains("- [x] -2026-09-10 Changed externally"));

    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 5},
            "contentChanges": [{"text": canonical}]
        }
    }));
    peer.send(json!({
        "jsonrpc": "2.0",
        "id": 50,
        "method": "workspace/executeCommand",
        "params": {"command": "todomd.changeView", "arguments": []}
    }));
    loop {
        let message = peer.read();
        if message["method"] == "window/showMessageRequest" {
            assert!(
                message["params"]["actions"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|action| action["title"] == "flat")
            );
            peer.send(json!({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": {"title": "flat"}
            }));
            break;
        }
    }
    let (flat, _) = receive_workspace_edit(&mut peer, "@Postgrad");
    assert!(!flat.contains("# Postgrad"));
    let response = read_response(&mut peer, 50);
    assert_eq!(response["result"], Value::Null);
    assert_eq!(case.hooks(), "apply\napply\n");

    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 6},
            "contentChanges": [{"text": flat}]
        }
    }));
    peer.send(json!({
        "jsonrpc": "2.0",
        "id": 51,
        "method": "workspace/executeCommand",
        "params": {"command": "todomd.changeView", "arguments": []}
    }));
    loop {
        let message = peer.read();
        if message["method"] == "window/showMessageRequest" {
            peer.send(json!({
                "jsonrpc": "2.0",
                "id": message["id"],
                "error": {"code": -32601, "message": "Method not found"}
            }));
            break;
        }
    }
    let (default_view, _) = receive_workspace_edit(&mut peer, "# Postgrad");
    let response = read_response(&mut peer, 51);
    assert_eq!(response["result"], Value::Null);
    assert_eq!(case.hooks(), "apply\napply\n");

    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
            "textDocument": {"uri": uri, "version": 7},
            "contentChanges": [{"text": default_view}]
        }
    }));
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

fn read_response(peer: &mut LspPeer, id: u64) -> Value {
    loop {
        let message = peer.read();
        if message["id"] == id {
            return message;
        }
    }
}

fn receive_workspace_edit(peer: &mut LspPeer, expected: &str) -> (String, Vec<Value>) {
    let mut events = Vec::new();
    for _ in 0..32 {
        let message = peer.read();
        if message["method"] == "window/workDoneProgress/create" {
            peer.send(json!({"jsonrpc": "2.0", "id": message["id"], "result": null}));
            continue;
        }
        if matches!(
            message["method"].as_str(),
            Some("$/progress" | "window/showMessage")
        ) {
            events.push(message);
            continue;
        }
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
        return (new_text, events);
    }
    panic!("server did not send a workspace edit");
}

fn assert_hook_follows_workspace_edit(peer: &mut LspPeer, earlier_events: &[Value]) {
    assert!(!earlier_events.iter().any(|event| {
        event["method"] == "$/progress"
            && event["params"]["value"]["message"] == "Running after_apply hook"
    }));

    let mut applied_message = false;
    let mut progress_started = false;
    for _ in 0..16 {
        let message = peer.read();
        if message["method"] == "window/workDoneProgress/create" {
            peer.send(json!({"jsonrpc": "2.0", "id": message["id"], "result": null}));
        } else if message["method"] == "window/showMessage"
            && message["params"]["message"]
                .as_str()
                .is_some_and(|text| text.starts_with("todomd: changes applied"))
        {
            applied_message = true;
        } else if message["method"] == "$/progress"
            && message["params"]["value"]["kind"] == "begin"
            && message["params"]["value"]["message"] == "Running after_apply hook"
        {
            assert!(applied_message);
            progress_started = true;
        } else if message["method"] == "$/progress"
            && message["params"]["value"]["kind"] == "end"
            && message["params"]["value"]["message"] == "after_apply hook finished"
        {
            assert!(progress_started);
            return;
        }
    }
    panic!("server did not finish after_apply progress");
}

fn receive_progress_end(peer: &mut LspPeer) -> (Value, Option<String>) {
    for _ in 0..16 {
        let message = peer.read();
        if message["method"] == "window/workDoneProgress/create" {
            peer.send(json!({"jsonrpc": "2.0", "id": message["id"], "result": null}));
            continue;
        }
        if message["method"] == "$/progress" && message["params"]["value"]["kind"] == "end" {
            return (
                message["params"]["token"].clone(),
                message["params"]["value"]["message"]
                    .as_str()
                    .map(str::to_owned),
            );
        }
    }
    panic!("server did not end work-done progress");
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
