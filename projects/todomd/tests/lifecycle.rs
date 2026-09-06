#![cfg(unix)]

use std::{
    fs::{self, File},
    io::{Read, Write},
    os::unix::{fs::PermissionsExt, process::CommandExt},
    path::{Path, PathBuf},
    process::{Child, Command, Output, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

use nix::{
    fcntl::{FcntlArg, OFlag, fcntl},
    pty::openpty,
    sys::signal::{Signal, kill},
    unistd::Pid,
};
use tempfile::TempDir;

struct Case {
    root: TempDir,
    calendars: PathBuf,
    config: PathBuf,
    hook_log: PathBuf,
    runtime: PathBuf,
    editor: PathBuf,
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
            "#!/bin/sh\nprintf '%s\\n' \"$2\" >> \"$1\"\n\
             if [ \"$2\" = apply ] && [ -n \"${TODOMD_REFRESH_MARKER:-}\" ]; then\n\
               grep -q \"$TODOMD_REFRESH_MARKER\" \"$4\"/todomd/session-*/tasks.md || exit 9\n\
             fi\n\
             exit \"$3\"\n",
        );
        let editor = root.path().join("editor");
        write_executable(
            &editor,
            "#!/bin/sh\ncat > \"$1\" <<'EOF'\n# Postgrad\n\n- [ ] New task\n\n# Personal\n\n- [x] Submit paper <!-- todomd:id=t1 -->\nEOF\n",
        );
        let config = root.path().join("config.toml");
        fs::write(
            &config,
            format!(
                "calendar_roots = [{calendars:?}]\n\
                 [hooks]\n\
                 before_session = [\"sh\", {hook:?}, {log:?}, \"before\", \"0\"]\n\
                 after_apply = [\"sh\", {hook:?}, {log:?}, \"apply\", \"{after_apply_status}\", {runtime:?}]\n\
                 after_session = [\"sh\", {hook:?}, {log:?}, \"after\", \"0\"]\n",
                calendars = calendars.to_string_lossy(),
                hook = hook.to_string_lossy(),
                log = hook_log.to_string_lossy(),
                runtime = runtime.to_string_lossy(),
            ),
        )
        .unwrap();

        Self {
            root,
            calendars,
            config,
            hook_log,
            runtime,
            editor,
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
fn no_change_runs_session_hooks_without_after_apply() {
    let case = Case::new(0);
    let output = case.edit_command("true").output().unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    assert_eq!(case.hooks(), "before\nafter\n");
    assert!(String::from_utf8_lossy(&output.stderr).contains("todomd: no changes"));
}

#[test]
fn a_bare_invocation_edits_every_discovered_list() {
    let case = Case::new(0);
    let mut command = case.base("true");
    let output = command.output().unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    assert_eq!(case.hooks(), "before\nafter\n");
    assert!(String::from_utf8_lossy(&output.stderr).contains("todomd: no changes"));
}

#[test]
fn show_prints_every_list_as_json_without_hooks_or_a_terminal() {
    let case = Case::new(0);
    let output = case.base("false").arg("show").output().unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    assert!(!case.hook_log.exists());

    let tasks: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let tasks = tasks.as_array().unwrap();
    assert_eq!(tasks.len(), 2);
    assert_eq!(tasks[0]["list"], "Personal");
    assert_eq!(tasks[0]["summary"], "Buy milk, bread");
    assert_eq!(tasks[0]["completed"], false);
    assert_eq!(
        tasks[0]["file"],
        case.calendars
            .join("Personal/groceries.ics")
            .to_str()
            .unwrap()
    );
    assert_eq!(tasks[1]["list"], "Postgrad");
    assert_eq!(tasks[1]["uid"], "write@example.test");
}

#[test]
fn show_reports_tasks_it_cannot_render_without_breaking_json() {
    let case = Case::new(0);
    let output = case
        .base("false")
        .args(["show", "Postgrad"])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("1 task without a summary not shown"),
        "{stderr}"
    );
    assert!(stderr.contains("nosummary.ics"), "{stderr}");

    let tasks: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let tasks = tasks.as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["uid"], "write@example.test");
}

#[test]
fn show_completed_includes_finished_tasks() {
    let case = Case::new(0);
    let output = case
        .base("false")
        .args(["show", "--completed", "Postgrad"])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    let tasks: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let tasks = tasks.as_array().unwrap();
    assert_eq!(tasks.len(), 2);
    let done = tasks
        .iter()
        .find(|task| task["uid"] == "read@example.test")
        .unwrap();
    assert_eq!(done["completed"], true);
    assert_eq!(done["summary"], "Read chapter four");
}

#[test]
fn edit_completed_renders_and_reopens_finished_tasks() {
    let case = Case::new(0);
    let reopen = case.root.path().join("reopen-editor");
    write_executable(
        &reopen,
        "#!/bin/sh\n\
         set -eu\n\
         grep -q '^- \\[x\\] Read chapter four' \"$1\"\n\
         sed -i 's/^- \\[x\\] Read chapter four/- [ ] Read chapter four/' \"$1\"\n",
    );
    let mut command = case.base(reopen.to_str().unwrap());
    command.args(["edit", "--completed", "Postgrad", "Personal"]);
    let output = run_in_pty(&mut command, b"y\n");
    let text = output_text(&output);

    assert!(output.status.success(), "{text}");
    assert!(text.contains("reopened  Read chapter four"), "{text}");
    let reopened = fs::read_to_string(case.calendars.join("Postgrad/read.ics")).unwrap();
    assert!(reopened.contains("STATUS:NEEDS-ACTION"), "{reopened}");
    assert!(!reopened.contains("PERCENT-COMPLETE"), "{reopened}");
    assert!(reopened.contains("X-PRESERVED:yes"), "{reopened}");
}

#[test]
fn edit_hides_completed_tasks_by_default() {
    let case = Case::new(0);
    let check = case.root.path().join("assert-editor");
    write_executable(
        &check,
        "#!/bin/sh\nif grep -q 'Read chapter four' \"$1\"; then exit 1; fi\nexit 0\n",
    );

    let output = case.base(check.to_str().unwrap()).output().unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    assert!(String::from_utf8_lossy(&output.stderr).contains("todomd: no changes"));
}

#[test]
fn show_accepts_selected_lists() {
    let case = Case::new(0);
    let output = case
        .base("false")
        .args(["show", "Postgrad"])
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    let tasks: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(tasks.as_array().unwrap().len(), 1);
    assert_eq!(tasks[0]["list"], "Postgrad");
}

#[test]
fn a_list_name_is_not_mistaken_for_a_subcommand() {
    let case = Case::new(0);
    let output = case.base("true").arg("Postgrad").output().unwrap();

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("unrecognized subcommand"));
    assert!(!case.hook_log.exists());
}

#[test]
fn a_created_task_keeps_the_priority_it_was_written_with() {
    let case = Case::new(0);
    let editor = case.root.path().join("prio-editor");
    write_executable(
        &editor,
        "#!/bin/sh\ncat > \"$1\" <<'EOF'\n# Postgrad\n\n- [ ] !!! Foo\n- [ ] Plain\n- [ ] Write paper draft <!-- todomd:id=t1 -->\n\n# Personal\n\n- [ ] Buy milk, bread <!-- todomd:id=t2 -->\nEOF\n",
    );

    let output = run_in_pty(&mut case.edit_command(editor.to_str().unwrap()), b"y\n");
    let text = output_text(&output);

    assert!(output.status.success(), "{text}");
    assert!(text.contains("created   Foo (!!!)"), "{text}");
    assert!(text.contains("created   Plain"), "{text}");
    assert!(!text.contains("created   Plain ("), "{text}");

    let created = fs::read_dir(case.calendars.join("Postgrad"))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "ics"))
        .map(|path| fs::read_to_string(path).unwrap())
        .filter(|contents| contents.contains("SUMMARY:Foo") || contents.contains("SUMMARY:Plain"))
        .collect::<Vec<_>>();
    assert_eq!(created.len(), 2, "{created:?}");

    let foo = created
        .iter()
        .find(|contents| contents.contains("SUMMARY:Foo"))
        .unwrap();
    assert!(foo.contains("PRIORITY:1"), "{foo}");

    let plain = created
        .iter()
        .find(|contents| contents.contains("SUMMARY:Plain"))
        .unwrap();
    assert!(!plain.contains("PRIORITY"), "{plain}");

    // The marker also survives the round trip back out of the vdir.
    let shown = case.base("false").arg("show").output().unwrap();
    let tasks: serde_json::Value = serde_json::from_slice(&shown.stdout).unwrap();
    let foo = tasks
        .as_array()
        .unwrap()
        .iter()
        .find(|task| task["summary"] == "Foo")
        .unwrap();
    assert_eq!(foo["priority"], "high");
}

#[test]
fn editor_failure_retains_the_session_and_runs_cleanup() {
    let case = Case::new(0);
    let output = case.edit_command("false").output().unwrap();

    assert!(!output.status.success());
    assert_eq!(case.hooks(), "before\nafter\n");
    assert!(String::from_utf8_lossy(&output.stderr).contains("session retained at"));
}

#[test]
fn no_hooks_bypasses_every_configured_hook() {
    let case = Case::new(0);
    let output = case
        .edit_command("true")
        .arg("--no-hooks")
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", output_text(&output));
    assert!(!case.hook_log.exists());
}

#[test]
fn rejected_plan_changes_no_sources_and_runs_cleanup() {
    let case = Case::new(0);
    let before = source_contents(&case.calendars);
    let mut command = case.edit_command(case.editor.to_str().unwrap());
    let output = run_in_pty(&mut command, b"n\n");

    assert!(output.status.success(), "{}", output_text(&output));
    assert_eq!(source_contents(&case.calendars), before);
    assert_eq!(case.hooks(), "before\nafter\n");
    assert!(output_text(&output).contains("changes cancelled"));
}

#[test]
fn confirmed_plan_refreshes_a_retained_session_before_hooks_finish() {
    let case = Case::new(0);
    let mut command = case.edit_command(case.editor.to_str().unwrap());
    command
        .arg("--keep")
        .env("TODOMD_REFRESH_MARKER", "New task <!-- todomd:id=t3 -->");
    let output = run_in_pty(&mut command, b"y\n");
    let text = output_text(&output);

    assert!(output.status.success(), "{text}");
    assert_eq!(case.hooks(), "before\napply\nafter\n");
    let session = retained_session(&text);
    let tasks = fs::read_to_string(session.join("tasks.md")).unwrap();
    assert!(tasks.contains("New task <!-- todomd:id=t3 -->"));
    assert!(!tasks.contains("Submit paper"));
    assert!(!tasks.contains("Buy milk"));

    let baseline: serde_json::Value =
        serde_json::from_slice(&fs::read(session.join("baseline.json")).unwrap()).unwrap();
    let uid = baseline["lists"][0]["tasks"][0]["id"].as_str().unwrap();
    let manifest: serde_json::Value =
        serde_json::from_slice(&fs::read(session.join("manifest.json")).unwrap()).unwrap();
    assert_eq!(manifest["ids"][uid], "t3");
    assert!(
        case.calendars
            .join("Postgrad")
            .join(format!("{uid}.ics"))
            .is_file()
    );
    assert_complete_apply(&case.calendars);
}

#[test]
fn after_apply_failure_keeps_applied_sources_and_runs_cleanup() {
    let case = Case::new(7);
    let mut command = case.edit_command(case.editor.to_str().unwrap());
    let output = run_in_pty(&mut command, b"y\n");
    let text = output_text(&output);

    assert!(!output.status.success());
    assert_eq!(case.hooks(), "before\napply\nafter\n");
    assert!(text.contains("after_apply hook exited unsuccessfully"));
    assert!(text.contains("session retained at"));
    assert_complete_apply(&case.calendars);
}

#[test]
fn sigterm_interrupts_the_editor_and_runs_cleanup() {
    let case = Case::new(0);
    let sleeper = case.root.path().join("sleep-editor");
    let editor_started = case.root.path().join("editor-started");
    write_executable(
        &sleeper,
        &format!(
            "#!/bin/sh\nprintf running > {editor_started:?}\nexec sleep 30\n",
            editor_started = editor_started.to_string_lossy()
        ),
    );
    let mut command = case.edit_command(sleeper.to_str().unwrap());
    command
        .process_group(0)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let child = command.spawn().unwrap();
    if !wait_for_file(&editor_started) {
        let pid = i32::try_from(child.id()).unwrap();
        let _ = kill(Pid::from_raw(-pid), Signal::SIGKILL);
        let _ = child.wait_with_output();
        panic!("timed out waiting for the editor to start");
    }

    kill(
        Pid::from_raw(i32::try_from(child.id()).unwrap()),
        Signal::SIGTERM,
    )
    .unwrap();
    let output = wait_with_timeout(child, Duration::from_secs(5));
    let text = output_text(&output);

    assert!(!output.status.success());
    assert_eq!(case.hooks(), "before\nafter\n");
    assert!(text.contains("termination requested"));
    assert!(text.contains("session retained at"));
}

fn run_in_pty(command: &mut Command, input: &[u8]) -> Output {
    let pty = openpty(None, None).unwrap();
    let mut master = File::from(pty.master);
    let slave = File::from(pty.slave);
    command
        .stdin(Stdio::from(slave.try_clone().unwrap()))
        .stdout(Stdio::from(slave.try_clone().unwrap()))
        .stderr(Stdio::from(slave.try_clone().unwrap()));
    command.process_group(0);
    let mut child = command.spawn().unwrap();
    drop(slave);
    fcntl(&master, FcntlArg::F_SETFL(OFlag::O_NONBLOCK)).unwrap();

    let mut bytes = Vec::new();
    let mut answered = false;
    let deadline = Instant::now() + Duration::from_secs(10);
    let status = loop {
        drain_pty(&mut master, &mut bytes);
        if !answered && String::from_utf8_lossy(&bytes).contains("Apply these changes? [y/N]") {
            master.write_all(input).unwrap();
            answered = true;
        }
        if let Some(status) = child.try_wait().unwrap() {
            drain_pty(&mut master, &mut bytes);
            break status;
        }
        if Instant::now() >= deadline {
            let pid = i32::try_from(child.id()).unwrap();
            let _ = kill(Pid::from_raw(-pid), Signal::SIGKILL);
            let _ = child.wait();
            panic!("PTY child timed out");
        }
        thread::sleep(Duration::from_millis(10));
    };
    Output {
        status,
        stdout: bytes,
        stderr: Vec::new(),
    }
}

fn drain_pty(master: &mut File, output: &mut Vec<u8>) {
    let mut buffer = [0; 4096];
    loop {
        match master.read(&mut buffer) {
            Ok(0) => break,
            Ok(read) => output.extend_from_slice(&buffer[..read]),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => break,
            Err(error) if error.raw_os_error() == Some(nix::libc::EIO) => break,
            Err(error) => panic!("failed to read PTY: {error}"),
        }
    }
}

fn wait_with_timeout(child: Child, timeout: Duration) -> Output {
    let pid = i32::try_from(child.id()).unwrap();
    let (finished, receiver) = mpsc::channel();
    let watchdog = thread::spawn(move || {
        if receiver.recv_timeout(timeout).is_err() {
            let _ = kill(Pid::from_raw(-pid), Signal::SIGKILL);
        }
    });
    let output = child.wait_with_output().unwrap();
    let _ = finished.send(());
    watchdog.join().unwrap();
    output
}

fn wait_for_file(path: &Path) -> bool {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !path.exists() {
        if Instant::now() >= deadline {
            return false;
        }
        thread::sleep(Duration::from_millis(10));
    }
    true
}

fn retained_session(output: &str) -> PathBuf {
    let marker = "session retained at ";
    let remainder = output.split(marker).nth(1).expect("retained session path");
    PathBuf::from(remainder.split_whitespace().next().unwrap())
}

fn source_contents(root: &Path) -> Vec<(PathBuf, Vec<u8>)> {
    let mut files = Vec::new();
    collect_files(root, root, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn collect_files(root: &Path, directory: &Path, files: &mut Vec<(PathBuf, Vec<u8>)>) {
    for entry in fs::read_dir(directory).unwrap() {
        let entry = entry.unwrap();
        if entry.file_type().unwrap().is_dir() {
            collect_files(root, &entry.path(), files);
        } else {
            files.push((
                entry.path().strip_prefix(root).unwrap().to_path_buf(),
                fs::read(entry.path()).unwrap(),
            ));
        }
    }
}

fn assert_complete_apply(calendars: &Path) {
    assert!(!calendars.join("Postgrad/write.ics").exists());
    assert!(!calendars.join("Personal/groceries.ics").exists());
    let moved = fs::read_to_string(calendars.join("Personal/write.ics")).unwrap();
    assert!(moved.contains("SUMMARY:Submit paper"));
    assert!(moved.contains("STATUS:COMPLETED"));
    assert!(moved.contains("DUE;VALUE=DATE:20260910"));
    assert!(moved.contains("X-TODOMD-TEST;ANSWER=42:preserve me"));
    assert!(moved.contains("BEGIN:VALARM"));
    assert_eq!(
        fs::read_dir(calendars.join("Postgrad"))
            .unwrap()
            .filter(|entry| {
                entry
                    .as_ref()
                    .unwrap()
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "ics")
            })
            .count(),
        4
    );
    assert_eq!(
        fs::read_dir(calendars.join("Personal"))
            .unwrap()
            .filter(|entry| {
                entry
                    .as_ref()
                    .unwrap()
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "ics")
            })
            .count(),
        1
    );
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
