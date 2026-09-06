use std::{
    collections::BTreeMap,
    fmt, fs,
    io::{self, IsTerminal, Write},
    path::{Path, PathBuf},
    sync::mpsc,
    thread,
    time::Duration,
};

use anyhow::{Context, Result, bail};
use chrono::{DateTime, Utc};
use icalendar::{
    Calendar, Component as IcalComponent, Todo, TodoStatus,
    parser::{Component as ParsedComponent, Property as ParsedProperty, read_calendar, unfold},
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use tempfile::NamedTempFile;
use uuid::Uuid;

use super::planner::{ChangePlan, Operation};
use crate::{
    model::{Priority, TaskId},
    repository::{SourceSnapshot, verify_snapshot},
};

#[derive(Clone, Debug, Serialize)]
pub enum FileAction {
    Create,
    Modify,
    Move,
    Delete,
}

#[derive(Clone, Debug, Serialize)]
pub struct StagedFileChange {
    action: FileAction,
    source: Option<PathBuf>,
    source_sha256: Option<[u8; 32]>,
    destination: Option<PathBuf>,
    staged: Option<PathBuf>,
    staged_sha256: Option<[u8; 32]>,
    backup: Option<PathBuf>,
}

#[derive(Clone, Debug)]
pub struct StagedTransaction {
    changes: Vec<StagedFileChange>,
    created_tasks: BTreeMap<usize, TaskId>,
    root: PathBuf,
}

#[derive(Default)]
struct ExistingEdit {
    summary: Option<String>,
    completion: CompletionChange,
    priority: Option<Priority>,
    move_to: Option<String>,
    delete: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum CompletionChange {
    #[default]
    Unchanged,
    Complete,
    Reopen,
}

#[derive(Serialize)]
struct PersistedPlan<'a> {
    semantic: &'a ChangePlan,
    files: &'a [StagedFileChange],
    created_tasks: &'a BTreeMap<usize, TaskId>,
}

pub fn stage(
    plan: &ChangePlan,
    sources: &SourceSnapshot,
    session_root: &Path,
    now: DateTime<Utc>,
) -> Result<StagedTransaction> {
    let root = session_root.join("transactions/0001");
    let staged_dir = root.join("staged");
    let backup_dir = root.join("backup");
    fs::create_dir(&root)
        .with_context(|| format!("failed to create transaction {}", root.display()))?;
    fs::create_dir(&staged_dir)
        .with_context(|| format!("failed to create {}", staged_dir.display()))?;
    fs::create_dir(&backup_dir)
        .with_context(|| format!("failed to create {}", backup_dir.display()))?;

    let mut existing: BTreeMap<TaskId, ExistingEdit> = BTreeMap::new();
    let mut creates = Vec::new();
    for operation in &plan.operations {
        match operation {
            Operation::Rename { id, to, .. } => {
                existing.entry(id.clone()).or_default().summary = Some(to.clone());
            }
            Operation::Complete { id, .. } => {
                existing.entry(id.clone()).or_default().completion = CompletionChange::Complete;
            }
            Operation::Reopen { id, .. } => {
                existing.entry(id.clone()).or_default().completion = CompletionChange::Reopen;
            }
            Operation::Reprioritize { id, to, .. } => {
                existing.entry(id.clone()).or_default().priority = Some(*to);
            }
            Operation::Move { id, to, .. } => {
                existing.entry(id.clone()).or_default().move_to = Some(to.clone());
            }
            Operation::Delete { id, .. } => {
                existing.entry(id.clone()).or_default().delete = true;
            }
            Operation::Create {
                draft_id,
                list,
                summary,
                priority,
            } => creates.push((*draft_id, list, summary, *priority)),
        }
    }

    let mut changes = Vec::new();
    for (task_id, edit) in existing {
        let source = sources.file_for_task(&task_id).with_context(|| {
            format!(
                "source snapshot has no file for VTODO {:?}",
                task_id.as_str()
            )
        })?;
        let index = changes.len() + 1;
        let backup = backup_dir.join(format!("{index:04}.ics"));

        if edit.delete {
            changes.push(StagedFileChange {
                action: FileAction::Delete,
                source: Some(source.path.clone()),
                source_sha256: Some(source.sha256),
                destination: None,
                staged: None,
                staged_sha256: None,
                backup: Some(backup),
            });
            continue;
        }

        let destination_list = edit.move_to.as_deref().unwrap_or(&source.list_name);
        let destination_dir = sources
            .list_dirs
            .get(destination_list)
            .with_context(|| format!("unknown destination list {destination_list:?}"))?;
        let filename = source
            .path
            .file_name()
            .context("source VTODO path has no filename")?;
        let destination = destination_dir.join(filename);
        if destination != source.path && destination.exists() {
            bail!("move destination {} already exists", destination.display());
        }

        let contents = if edit.summary.is_some()
            || edit.completion != CompletionChange::Unchanged
            || edit.priority.is_some()
        {
            patch_existing(
                &source.contents,
                &task_id,
                edit.summary.as_deref(),
                edit.completion,
                edit.priority,
                now,
            )?
        } else {
            source.contents.clone()
        };
        let staged = staged_dir.join(format!("{index:04}.ics"));
        let staged_sha256 = hash_bytes(contents.as_bytes());
        fs::write(&staged, contents)
            .with_context(|| format!("failed to write staged file {}", staged.display()))?;
        let action = if destination == source.path {
            FileAction::Modify
        } else {
            FileAction::Move
        };
        changes.push(StagedFileChange {
            action,
            source: Some(source.path.clone()),
            source_sha256: Some(source.sha256),
            destination: Some(destination),
            staged: Some(staged),
            staged_sha256: Some(staged_sha256),
            backup: Some(backup),
        });
    }

    let mut created_tasks = BTreeMap::new();
    for (draft_id, list, summary, priority) in creates {
        let task_id = TaskId::new(Uuid::new_v4().to_string());
        let destination_dir = sources
            .list_dirs
            .get(list)
            .with_context(|| format!("unknown destination list {list:?}"))?;
        let destination = destination_dir.join(format!("{}.ics", task_id.as_str()));
        if destination.exists() {
            bail!(
                "create destination {} already exists",
                destination.display()
            );
        }

        let index = changes.len() + 1;
        let staged = staged_dir.join(format!("{index:04}.ics"));
        let contents = new_todo(&task_id, summary, priority, now);
        let staged_sha256 = hash_bytes(contents.as_bytes());
        fs::write(&staged, contents)
            .with_context(|| format!("failed to write staged file {}", staged.display()))?;
        changes.push(StagedFileChange {
            action: FileAction::Create,
            source: None,
            source_sha256: None,
            destination: Some(destination),
            staged: Some(staged),
            staged_sha256: Some(staged_sha256),
            backup: None,
        });
        created_tasks.insert(draft_id, task_id);
    }

    let transaction = StagedTransaction {
        changes,
        created_tasks,
        root,
    };
    transaction.write_plan(plan)?;
    Ok(transaction)
}

pub fn apply(transaction: &StagedTransaction, sources: &SourceSnapshot) -> Result<()> {
    verify_snapshot(sources)?;

    for change in &transaction.changes {
        if change.source.is_some() {
            backup_source(change)?;
        }
    }

    for (index, change) in transaction.changes.iter().enumerate() {
        if let Err(error) = verify_change_preconditions(change).and_then(|()| apply_change(change))
        {
            let rollback_errors = rollback(&transaction.changes[..index]);
            if rollback_errors.is_empty() {
                return Err(error.context("apply failed; completed operations were rolled back"));
            }
            bail!(
                "apply failed: {error:#}; rollback also failed: {}",
                rollback_errors.join("; ")
            );
        }
    }

    Ok(())
}

pub fn confirm(interrupted: impl Fn() -> bool) -> Result<bool> {
    if !io::stdin().is_terminal() || !io::stderr().is_terminal() {
        bail!("confirmation requires an interactive terminal");
    }

    eprint!("\nApply these changes? [y/N] ");
    io::stderr()
        .flush()
        .context("failed to flush confirmation prompt")?;

    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut answer = String::new();
        let result = io::stdin().read_line(&mut answer).map(|_| answer);
        let _ = sender.send(result);
    });
    loop {
        match receiver.recv_timeout(Duration::from_millis(50)) {
            Ok(answer) => {
                return Ok(is_confirmed(
                    &answer.context("failed to read confirmation")?,
                ));
            }
            Err(mpsc::RecvTimeoutError::Timeout) if interrupted() => {
                bail!("termination requested");
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                bail!("confirmation reader stopped unexpectedly");
            }
        }
    }
}

impl StagedTransaction {
    fn write_plan(&self, plan: &ChangePlan) -> Result<()> {
        let persisted = PersistedPlan {
            semantic: plan,
            files: &self.changes,
            created_tasks: &self.created_tasks,
        };
        let mut json = serde_json::to_vec_pretty(&persisted).context("failed to serialize plan")?;
        json.push(b'\n');
        let path = self.root.join("plan.json");
        fs::write(&path, json).with_context(|| format!("failed to write {}", path.display()))
    }
}

impl fmt::Display for StagedTransaction {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(formatter, "Files:")?;
        for change in &self.changes {
            match (&change.action, &change.source, &change.destination) {
                (FileAction::Create, _, Some(destination)) => {
                    writeln!(formatter, "  create {}", destination.display())?;
                }
                (FileAction::Modify, Some(source), _) => {
                    writeln!(formatter, "  modify {}", source.display())?;
                }
                (FileAction::Move, Some(source), Some(destination)) => {
                    writeln!(
                        formatter,
                        "  move   {} -> {}",
                        source.display(),
                        destination.display()
                    )?;
                }
                (FileAction::Delete, Some(source), _) => {
                    writeln!(formatter, "  delete {}", source.display())?;
                }
                _ => return Err(fmt::Error),
            }
        }
        Ok(())
    }
}

fn patch_existing(
    contents: &str,
    task_id: &TaskId,
    summary: Option<&str>,
    completion: CompletionChange,
    priority: Option<Priority>,
    now: DateTime<Utc>,
) -> Result<String> {
    let unfolded = unfold(contents);
    let mut calendar = read_calendar(&unfolded).map_err(anyhow::Error::msg)?;
    let matching = calendar
        .components
        .iter()
        .enumerate()
        .filter(|(_, component)| {
            component.name.as_str().eq_ignore_ascii_case("VTODO")
                && component
                    .find_prop("UID")
                    .is_some_and(|property| property.val.as_str() == task_id.as_str())
        })
        .map(|(index, _)| index)
        .collect::<Vec<_>>();
    let index = match matching.as_slice() {
        [index] => *index,
        [] => bail!(
            "staged file no longer contains VTODO {:?}",
            task_id.as_str()
        ),
        _ => bail!(
            "staged file contains duplicate VTODO {:?}",
            task_id.as_str()
        ),
    };
    let todo = &mut calendar.components[index];

    if let Some(summary) = summary {
        set_property(todo, "SUMMARY", summary)?;
    }
    // Only written when the marker changed, so values like PRIORITY:4 survive
    // edits that leave the level alone.
    if let Some(priority) = priority {
        match priority.to_ics() {
            Some(value) => set_property(todo, "PRIORITY", value)?,
            None => remove_property(todo, "PRIORITY"),
        }
    }

    match completion {
        CompletionChange::Unchanged => {}
        CompletionChange::Complete => {
            set_property(todo, "STATUS", "COMPLETED")?;
            set_property(todo, "COMPLETED", &format_timestamp(now))?;
            set_property(todo, "PERCENT-COMPLETE", "100")?;
        }
        CompletionChange::Reopen => {
            set_property(todo, "STATUS", "NEEDS-ACTION")?;
            remove_property(todo, "COMPLETED");
            remove_property(todo, "PERCENT-COMPLETE");
        }
    }

    let sequence = optional_property(todo, "SEQUENCE")?
        .map(|value| value.parse::<u32>())
        .transpose()
        .context("VTODO SEQUENCE is not an unsigned integer")?
        .unwrap_or(0)
        .checked_add(1)
        .context("VTODO SEQUENCE overflow")?;
    set_property(todo, "SEQUENCE", &sequence.to_string())?;
    set_property(todo, "DTSTAMP", &format_timestamp(now))?;
    set_property(todo, "LAST-MODIFIED", &format_timestamp(now))?;

    Ok(Calendar::from(calendar).to_string())
}

fn remove_property(component: &mut ParsedComponent<'_>, name: &str) {
    component
        .properties
        .retain(|property| !property.name.as_str().eq_ignore_ascii_case(name));
}

fn set_property(component: &mut ParsedComponent<'_>, name: &str, value: &str) -> Result<()> {
    let matching = component
        .properties
        .iter()
        .enumerate()
        .filter(|(_, property)| property.name.as_str().eq_ignore_ascii_case(name))
        .map(|(index, _)| index)
        .collect::<Vec<_>>();
    match matching.as_slice() {
        [] => component.properties.push(ParsedProperty {
            name: name.to_owned().into(),
            val: value.to_owned().into(),
            params: Vec::new(),
        }),
        [index] => component.properties[*index].val = value.to_owned().into(),
        _ => bail!("VTODO contains more than one {name} property"),
    }
    Ok(())
}

fn optional_property<'a>(
    component: &'a ParsedComponent<'_>,
    name: &str,
) -> Result<Option<&'a str>> {
    let values = component
        .properties
        .iter()
        .filter(|property| property.name.as_str().eq_ignore_ascii_case(name))
        .map(|property| property.val.as_str())
        .collect::<Vec<_>>();
    match values.as_slice() {
        [] => Ok(None),
        [value] => Ok(Some(*value)),
        _ => bail!("VTODO contains more than one {name} property"),
    }
}

fn new_todo(task_id: &TaskId, summary: &str, priority: Priority, now: DateTime<Utc>) -> String {
    let mut builder = Todo::new();
    let builder = builder
        .uid(task_id.as_str())
        .summary(summary)
        .status(TodoStatus::NeedsAction)
        .created(now)
        .timestamp(now)
        .last_modified(now)
        .sequence(0);
    if let Some(value) = priority.to_ics() {
        builder.add_property("PRIORITY", value);
    }
    let todo = builder.done();
    let mut calendar = Calendar::new();
    calendar.push(todo);
    calendar.to_string()
}

fn format_timestamp(timestamp: DateTime<Utc>) -> String {
    timestamp.format("%Y%m%dT%H%M%SZ").to_string()
}

fn is_confirmed(answer: &str) -> bool {
    matches!(answer.trim(), "y" | "Y")
}

fn backup_source(change: &StagedFileChange) -> Result<()> {
    let source = source(change)?;
    let expected = change
        .source_sha256
        .context("staged source hash is missing")?;
    let bytes = read_regular_file(source)?;
    if hash_bytes(&bytes) != expected {
        bail!("source file {} changed before backup", source.display());
    }
    let backup = change.backup.as_deref().context("backup path is missing")?;
    let mut file = fs::File::create(backup)
        .with_context(|| format!("failed to create backup {}", backup.display()))?;
    file.write_all(&bytes)
        .with_context(|| format!("failed to write backup {}", backup.display()))?;
    file.sync_all()
        .with_context(|| format!("failed to sync backup {}", backup.display()))
}

fn verify_change_preconditions(change: &StagedFileChange) -> Result<()> {
    if let Some(source) = &change.source {
        let expected = change
            .source_sha256
            .context("staged source hash is missing")?;
        ensure_hash(source, expected, "source")?;
    }
    if let Some(staged) = &change.staged {
        let expected = change
            .staged_sha256
            .context("staged content hash is missing")?;
        ensure_hash(staged, expected, "staged")?;
    }
    if matches!(change.action, FileAction::Create | FileAction::Move) {
        ensure_absent(destination(change)?, "destination")?;
    }
    Ok(())
}

fn apply_change(change: &StagedFileChange) -> Result<()> {
    match change.action {
        FileAction::Create => atomic_create(staged(change)?, destination(change)?),
        FileAction::Modify => atomic_replace(staged(change)?, source(change)?),
        FileAction::Move => {
            let destination = destination(change)?;
            atomic_create(staged(change)?, destination)?;
            let source = source(change)?;
            if let Err(error) = fs::remove_file(source) {
                let cleanup = remove_written_file(
                    destination,
                    change
                        .staged_sha256
                        .context("staged content hash is missing")?,
                );
                return match cleanup {
                    Ok(()) => {
                        Err(error).with_context(|| format!("failed to remove {}", source.display()))
                    }
                    Err(cleanup_error) => bail!(
                        "failed to remove {}: {error}; also failed to clean up {}: {cleanup_error:#}",
                        source.display(),
                        destination.display()
                    ),
                };
            }
            Ok(())
        }
        FileAction::Delete => {
            let source = source(change)?;
            fs::remove_file(source)
                .with_context(|| format!("failed to remove {}", source.display()))
        }
    }
}

fn rollback(changes: &[StagedFileChange]) -> Vec<String> {
    let mut errors = Vec::new();
    for change in changes.iter().rev() {
        if let Err(error) = rollback_change(change) {
            errors.push(format!("{error:#}"));
        }
    }
    errors
}

fn rollback_change(change: &StagedFileChange) -> Result<()> {
    match change.action {
        FileAction::Create => remove_written_file(
            destination(change)?,
            change
                .staged_sha256
                .context("staged content hash is missing")?,
        ),
        FileAction::Modify => {
            ensure_hash(
                source(change)?,
                change
                    .staged_sha256
                    .context("staged content hash is missing")?,
                "modified file during rollback",
            )?;
            atomic_replace_from_backup(change.backup.as_deref(), change.source.as_deref())
        }
        FileAction::Delete => {
            ensure_absent(source(change)?, "deleted source during rollback")?;
            atomic_replace_from_backup(change.backup.as_deref(), change.source.as_deref())
        }
        FileAction::Move => {
            remove_written_file(
                destination(change)?,
                change
                    .staged_sha256
                    .context("staged content hash is missing")?,
            )?;
            ensure_absent(source(change)?, "moved source during rollback")?;
            atomic_replace_from_backup(change.backup.as_deref(), change.source.as_deref())
        }
    }
}

fn atomic_create(staged: &Path, destination: &Path) -> Result<()> {
    let bytes = fs::read(staged)
        .with_context(|| format!("failed to read staged file {}", staged.display()))?;
    let parent = destination
        .parent()
        .context("destination has no parent directory")?;
    let mut temporary = NamedTempFile::new_in(parent)
        .with_context(|| format!("failed to create temporary file in {}", parent.display()))?;
    temporary.write_all(&bytes)?;
    temporary.as_file().sync_all()?;
    temporary
        .persist_noclobber(destination)
        .map_err(|error| error.error)
        .with_context(|| format!("failed to create {}", destination.display()))?;
    Ok(())
}

fn atomic_replace(staged: &Path, destination: &Path) -> Result<()> {
    let bytes = fs::read(staged)
        .with_context(|| format!("failed to read staged file {}", staged.display()))?;
    atomic_replace_bytes(&bytes, destination)
}

fn atomic_replace_bytes(bytes: &[u8], destination: &Path) -> Result<()> {
    let parent = destination
        .parent()
        .context("destination has no parent directory")?;
    let permissions = fs::metadata(destination)
        .ok()
        .map(|metadata| metadata.permissions());
    let mut temporary = NamedTempFile::new_in(parent)
        .with_context(|| format!("failed to create temporary file in {}", parent.display()))?;
    if let Some(permissions) = permissions {
        temporary.as_file().set_permissions(permissions)?;
    }
    temporary.write_all(bytes)?;
    temporary.as_file().sync_all()?;
    temporary
        .persist(destination)
        .map_err(|error| error.error)
        .with_context(|| format!("failed to replace {}", destination.display()))?;
    Ok(())
}

fn atomic_replace_from_backup(backup: Option<&Path>, destination: Option<&Path>) -> Result<()> {
    let backup = backup.context("rollback backup path is missing")?;
    let destination = destination.context("rollback destination path is missing")?;
    let bytes = fs::read(backup)
        .with_context(|| format!("failed to read rollback backup {}", backup.display()))?;
    atomic_replace_bytes(&bytes, destination)
}

fn hash_bytes(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}

fn read_regular_file(path: &Path) -> Result<Vec<u8>> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("failed to inspect {}", path.display()))?;
    if !metadata.file_type().is_file() {
        bail!("{} is not a regular file", path.display());
    }
    fs::read(path).with_context(|| format!("failed to read {}", path.display()))
}

fn ensure_hash(path: &Path, expected: [u8; 32], label: &str) -> Result<()> {
    let bytes = read_regular_file(path)?;
    if hash_bytes(&bytes) != expected {
        bail!("{label} {} changed", path.display());
    }
    Ok(())
}

fn ensure_absent(path: &Path, label: &str) -> Result<()> {
    match fs::symlink_metadata(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("failed to inspect {}", path.display())),
        Ok(_) => bail!("{label} {} unexpectedly exists", path.display()),
    }
}

fn remove_written_file(path: &Path, expected: [u8; 32]) -> Result<()> {
    match fs::symlink_metadata(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to inspect {}", path.display()));
        }
        Ok(_) => {}
    }
    ensure_hash(path, expected, "written file during rollback")?;
    fs::remove_file(path).with_context(|| format!("failed to remove {}", path.display()))
}

fn source(change: &StagedFileChange) -> Result<&Path> {
    change
        .source
        .as_deref()
        .context("staged source path is missing")
}

fn destination(change: &StagedFileChange) -> Result<&Path> {
    change
        .destination
        .as_deref()
        .context("staged destination path is missing")
}

fn staged(change: &StagedFileChange) -> Result<&Path> {
    change
        .staged
        .as_deref()
        .context("staged file path is missing")
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use crate::{
        config::Config,
        repository::{Scope, load_lists},
    };

    use super::super::{
        markdown::{IdentityManifest, parse, render},
        planner::{Reconciliation, reconcile},
    };
    use super::*;

    fn fixture_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/calendars")
    }

    fn copy_fixtures() -> tempfile::TempDir {
        let temporary = tempfile::tempdir().unwrap();
        for list in ["Postgrad", "Personal"] {
            let source = fixture_root().join(list);
            let destination = temporary.path().join(list);
            fs::create_dir(&destination).unwrap();
            for entry in fs::read_dir(source).unwrap() {
                let entry = entry.unwrap();
                fs::copy(entry.path(), destination.join(entry.file_name())).unwrap();
            }
        }
        temporary
    }

    fn plan_for(config: &Config, markdown: &str) -> (ChangePlan, SourceSnapshot) {
        plan_in_scope(config, markdown, Scope::Active)
    }

    fn plan_in_scope(
        config: &Config,
        markdown: &str,
        scope: Scope,
    ) -> (ChangePlan, SourceSnapshot) {
        let requested = vec!["Postgrad".to_owned(), "Personal".to_owned()];
        let (baseline, _) = load_lists(config, &requested, scope).unwrap();
        let mut manifest = IdentityManifest::default();
        render(&baseline, &mut manifest).unwrap();
        let edited = parse(markdown, &baseline, &manifest).unwrap();
        let (current, sources) = load_lists(config, &requested, scope).unwrap();
        let Reconciliation::Outgoing(plan) = reconcile(&baseline, &edited, &current).unwrap()
        else {
            panic!("expected outgoing plan");
        };
        (plan, sources)
    }

    #[test]
    fn applies_all_file_operations_and_preserves_hidden_properties() {
        let calendars = copy_fixtures();
        let config = Config::new(vec![calendars.path().to_path_buf()]).unwrap();
        let markdown = "# Postgrad\n\n- [ ] New task\n\n# Personal\n\n- [x] Submit paper <!-- todomd:id=t1 -->\n";
        let (plan, sources) = plan_for(&config, markdown);
        let session = tempfile::tempdir().unwrap();
        fs::create_dir(session.path().join("transactions")).unwrap();
        let now = DateTime::parse_from_rfc3339("2026-09-05T20:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let transaction = stage(&plan, &sources, session.path(), now).unwrap();

        apply(&transaction, &sources).unwrap();

        let moved = fs::read_to_string(calendars.path().join("Personal/write.ics")).unwrap();
        assert!(moved.contains("SUMMARY:Submit paper"));
        assert!(moved.contains("STATUS:COMPLETED"));
        assert!(moved.contains("DUE;VALUE=DATE:20260910"));
        assert!(moved.contains("X-TODOMD-TEST;ANSWER=42:preserve me"));
        assert!(moved.contains("BEGIN:VALARM"));
        assert!(moved.contains("TRIGGER:-PT15M"));
        assert!(moved.contains("SEQUENCE:1"));
        assert!(!calendars.path().join("Postgrad/write.ics").exists());
        assert!(!calendars.path().join("Personal/groceries.ics").exists());
        assert_eq!(transaction.created_tasks.len(), 1);
        let created_id = transaction.created_tasks.values().next().unwrap();
        assert!(
            calendars
                .path()
                .join(format!("Postgrad/{}.ics", created_id.as_str()))
                .is_file()
        );
        assert!(session.path().join("transactions/0001/plan.json").is_file());
    }

    #[test]
    fn reopening_clears_completion_and_keeps_hidden_properties() {
        let source = include_str!("../../tests/fixtures/calendars/Postgrad/read.ics");
        let now = DateTime::parse_from_rfc3339("2026-09-05T20:00:00Z")
            .unwrap()
            .with_timezone(&Utc);

        let patched = patch_existing(
            source,
            &TaskId::new("read@example.test"),
            None,
            CompletionChange::Reopen,
            None,
            now,
        )
        .unwrap();

        assert!(patched.contains("STATUS:NEEDS-ACTION"), "{patched}");
        assert!(!patched.contains("COMPLETED:"), "{patched}");
        assert!(!patched.contains("PERCENT-COMPLETE"), "{patched}");
        assert!(patched.contains("X-PRESERVED:yes"), "{patched}");
        assert!(patched.contains("SUMMARY:Read chapter four"), "{patched}");
    }

    #[test]
    fn applies_a_reopen_to_the_source_file() {
        let calendars = copy_fixtures();
        let config = Config::new(vec![calendars.path().to_path_buf()]).unwrap();
        let markdown = "# Postgrad\n\n\
            - [ ] Read chapter four <!-- todomd:id=t1 -->\n\
            - [ ] Write paper draft <!-- todomd:id=t2 -->\n\
            \n\
            # Personal\n\n\
            - [ ] Buy milk, bread <!-- todomd:id=t3 -->\n";
        let (plan, sources) = plan_in_scope(&config, markdown, Scope::All);
        let session = tempfile::tempdir().unwrap();
        fs::create_dir(session.path().join("transactions")).unwrap();
        let now = DateTime::parse_from_rfc3339("2026-09-05T20:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let transaction = stage(&plan, &sources, session.path(), now).unwrap();

        apply(&transaction, &sources).unwrap();

        let reopened = fs::read_to_string(calendars.path().join("Postgrad/read.ics")).unwrap();
        assert!(reopened.contains("STATUS:NEEDS-ACTION"), "{reopened}");
        assert!(!reopened.contains("PERCENT-COMPLETE"), "{reopened}");
        assert!(reopened.contains("X-PRESERVED:yes"), "{reopened}");
    }

    const PRIORITISED: &str = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//todomd test//EN\r\nBEGIN:VTODO\r\nUID:prio@example.test\r\nSUMMARY:Prioritised\r\nPRIORITY:4\r\nSTATUS:NEEDS-ACTION\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";

    fn patch_priority(priority: Option<Priority>, summary: Option<&str>) -> String {
        let now = DateTime::parse_from_rfc3339("2026-09-05T20:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        patch_existing(
            PRIORITISED,
            &TaskId::new("prio@example.test"),
            summary,
            CompletionChange::Unchanged,
            priority,
            now,
        )
        .unwrap()
    }

    #[test]
    fn a_new_task_is_written_with_its_priority() {
        let now = DateTime::parse_from_rfc3339("2026-09-05T20:00:00Z")
            .unwrap()
            .with_timezone(&Utc);

        let high = new_todo(&TaskId::new("new"), "Foo", Priority::High, now);
        assert!(high.contains("PRIORITY:1"), "{high}");
        assert!(high.contains("SUMMARY:Foo"), "{high}");

        let low = new_todo(&TaskId::new("new"), "Foo", Priority::Low, now);
        assert!(low.contains("PRIORITY:9"), "{low}");

        let none = new_todo(&TaskId::new("new"), "Foo", Priority::None, now);
        assert!(!none.contains("PRIORITY"), "{none}");
    }

    #[test]
    fn keeps_an_uncanonical_priority_when_the_level_is_unchanged() {
        // PRIORITY:4 buckets to !!!, so an unrelated rename must not rewrite it.
        let patched = patch_priority(None, Some("Renamed"));

        assert!(patched.contains("PRIORITY:4"), "{patched}");
        assert!(patched.contains("SUMMARY:Renamed"), "{patched}");
    }

    #[test]
    fn writes_a_canonical_priority_when_the_level_changes() {
        let lowered = patch_priority(Some(Priority::Low), None);
        assert!(lowered.contains("PRIORITY:9"), "{lowered}");
        assert!(!lowered.contains("PRIORITY:4"), "{lowered}");

        let medium = patch_priority(Some(Priority::Medium), None);
        assert!(medium.contains("PRIORITY:5"), "{medium}");

        let high = patch_priority(Some(Priority::High), None);
        assert!(high.contains("PRIORITY:1"), "{high}");
    }

    #[test]
    fn removes_the_property_when_the_marker_is_dropped() {
        let patched = patch_priority(Some(Priority::None), None);

        assert!(!patched.contains("PRIORITY"), "{patched}");
        assert!(patched.contains("SUMMARY:Prioritised"), "{patched}");
    }

    #[test]
    fn escapes_edited_summary_text() {
        let source = include_str!("../../tests/fixtures/calendars/Postgrad/write.ics");
        let now = DateTime::parse_from_rfc3339("2026-09-05T20:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let patched = patch_existing(
            source,
            &TaskId::new("write@example.test"),
            Some(r"Comma, semicolon; slash\value"),
            CompletionChange::Unchanged,
            None,
            now,
        )
        .unwrap();

        assert!(
            patched.contains(r"SUMMARY:Comma\, semicolon\; slash\\value"),
            "{patched}"
        );
        let unfolded = unfold(&patched);
        let calendar = read_calendar(&unfolded).unwrap();
        let todo = calendar
            .components
            .iter()
            .find(|component| component.name.as_str() == "VTODO")
            .unwrap();
        assert_eq!(
            todo.find_prop("SUMMARY").unwrap().val.as_str(),
            r"Comma, semicolon; slash\value"
        );
    }

    #[test]
    fn refuses_to_apply_when_any_selected_source_changed() {
        let calendars = copy_fixtures();
        let config = Config::new(vec![calendars.path().to_path_buf()]).unwrap();
        let markdown = "# Postgrad\n\n- [ ] Renamed <!-- todomd:id=t1 -->\n\n# Personal\n\n- [ ] Buy milk, bread <!-- todomd:id=t2 -->\n";
        let (plan, sources) = plan_for(&config, markdown);
        let session = tempfile::tempdir().unwrap();
        fs::create_dir(session.path().join("transactions")).unwrap();
        let transaction = stage(&plan, &sources, session.path(), Utc::now()).unwrap();
        fs::write(
            calendars.path().join("Postgrad/event.ics"),
            "changed outside todomd",
        )
        .unwrap();

        assert!(apply(&transaction, &sources).is_err());
        let original = fs::read_to_string(calendars.path().join("Postgrad/write.ics")).unwrap();
        assert!(original.contains("SUMMARY:Write paper draft"));
    }

    #[test]
    fn refuses_to_apply_when_a_selected_list_changes_identity() {
        let calendars = copy_fixtures();
        let config = Config::new(vec![calendars.path().to_path_buf()]).unwrap();
        let markdown = "# Postgrad\n\n- [ ] Renamed <!-- todomd:id=t1 -->\n\n# Personal\n\n- [ ] Buy milk, bread <!-- todomd:id=t2 -->\n";
        let (plan, sources) = plan_for(&config, markdown);
        let session = tempfile::tempdir().unwrap();
        fs::create_dir(session.path().join("transactions")).unwrap();
        let transaction = stage(&plan, &sources, session.path(), Utc::now()).unwrap();
        fs::write(calendars.path().join("Postgrad/displayname"), "Elsewhere\n").unwrap();

        assert!(apply(&transaction, &sources).is_err());
        let original = fs::read_to_string(calendars.path().join("Postgrad/write.ics")).unwrap();
        assert!(original.contains("SUMMARY:Write paper draft"));
    }

    #[test]
    fn rolls_back_only_operations_that_succeeded() {
        let temporary = tempfile::tempdir().unwrap();
        let source = temporary.path().join("source.ics");
        let modified = temporary.path().join("modified.ics");
        let backup = temporary.path().join("backup.ics");
        let created = temporary.path().join("created.ics");
        let external_destination = temporary.path().join("external.ics");
        fs::write(&source, "original").unwrap();
        fs::write(&modified, "modified").unwrap();
        fs::write(&created, "created").unwrap();
        fs::write(&external_destination, "external").unwrap();
        let transaction = StagedTransaction {
            changes: vec![
                StagedFileChange {
                    action: FileAction::Modify,
                    source: Some(source.clone()),
                    source_sha256: Some(hash_bytes(b"original")),
                    destination: Some(source.clone()),
                    staged: Some(modified),
                    staged_sha256: Some(hash_bytes(b"modified")),
                    backup: Some(backup),
                },
                StagedFileChange {
                    action: FileAction::Create,
                    source: None,
                    source_sha256: None,
                    destination: Some(external_destination.clone()),
                    staged: Some(created),
                    staged_sha256: Some(hash_bytes(b"created")),
                    backup: None,
                },
            ],
            created_tasks: BTreeMap::new(),
            root: temporary.path().to_path_buf(),
        };

        assert!(apply(&transaction, &SourceSnapshot::default()).is_err());
        assert_eq!(fs::read_to_string(source).unwrap(), "original");
        assert_eq!(
            fs::read_to_string(external_destination).unwrap(),
            "external"
        );
    }

    #[test]
    fn failed_create_does_not_remove_an_existing_destination() {
        let temporary = tempfile::tempdir().unwrap();
        let staged = temporary.path().join("staged.ics");
        let destination = temporary.path().join("destination.ics");
        fs::write(&staged, "staged").unwrap();
        fs::write(&destination, "external").unwrap();
        let transaction = StagedTransaction {
            changes: vec![StagedFileChange {
                action: FileAction::Create,
                source: None,
                source_sha256: None,
                destination: Some(destination.clone()),
                staged: Some(staged),
                staged_sha256: Some(hash_bytes(b"staged")),
                backup: None,
            }],
            created_tasks: BTreeMap::new(),
            root: temporary.path().to_path_buf(),
        };

        assert!(apply(&transaction, &SourceSnapshot::default()).is_err());
        assert_eq!(fs::read_to_string(destination).unwrap(), "external");
    }

    #[test]
    fn confirmation_accepts_only_explicit_yes() {
        assert!(is_confirmed("y"));
        assert!(is_confirmed(" Y\n"));
        assert!(!is_confirmed(""));
        assert!(!is_confirmed("yes"));
    }
}
