use std::{
    env, fs,
    fs::{File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};

use anyhow::{Context, Error, Result, anyhow, bail};
use fs2::FileExt;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use tempfile::{Builder, NamedTempFile, TempDir};

use super::{
    RenderedSession,
    markdown::{self, IdentityManifest},
};
use crate::{config::Config, model::TaskState, repository::Scope, view::View};

pub const SESSION_FORMAT_VERSION: u32 = 3;
const SESSION_MARKER: &[u8] = b"todomd session\n";

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SessionMetadata {
    pub format_version: u32,
    pub config: Config,
    pub lists: Vec<String>,
    pub scope: Scope,
    pub hooks_enabled: bool,
    pub view: View,
}

#[derive(Debug)]
pub struct LoadedSession {
    pub root: PathBuf,
    pub metadata: SessionMetadata,
    pub manifest: IdentityManifest,
    pub baseline: TaskState,
    pub recovery_baseline: TaskState,
    pub accepted_text: String,
}

pub struct AcceptedState {
    pub text: String,
    pub manifest: IdentityManifest,
    pub baseline: TaskState,
    pub recovery_baseline: TaskState,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TasksUpdate {
    EditorManaged,
    ReplaceFile,
}

#[derive(Debug)]
pub struct Session {
    directory: TempDir,
    tasks_path: PathBuf,
}

impl Session {
    pub fn create(
        rendered: &RenderedSession,
        metadata: &SessionMetadata,
        recovery_baseline: &TaskState,
    ) -> Result<Self> {
        let (parent, is_private_parent) = session_parent();
        if is_private_parent {
            create_private_directory(&parent)?;
        }
        let session = Self::create_in(&parent, rendered)?;
        write_json(&session.path().join("live.json"), metadata)?;
        write_json(
            &session.path().join("recovery-baseline.json"),
            recovery_baseline,
        )?;
        fs::write(session.path().join("accepted.md"), &rendered.markdown)
            .context("failed to write accepted live document")?;
        Ok(session)
    }

    pub fn path(&self) -> &Path {
        self.directory.path()
    }

    pub fn tasks_path(&self) -> &Path {
        &self.tasks_path
    }

    pub fn is_attached(&self) -> bool {
        self.path().join("attached").is_file()
    }

    pub fn retain(self) -> PathBuf {
        self.directory.keep()
    }

    fn create_in(parent: &Path, rendered: &RenderedSession) -> Result<Self> {
        if !parent.is_dir() {
            anyhow::bail!("session parent {} is not a directory", parent.display());
        }

        let directory = Builder::new()
            .prefix("session-")
            .tempdir_in(parent)
            .with_context(|| format!("failed to create session below {}", parent.display()))?;
        restrict_directory(directory.path())?;
        fs::write(directory.path().join(".todomd-session"), SESSION_MARKER)
            .context("failed to write session marker")?;
        File::create(directory.path().join(".lock")).context("failed to create session lock")?;

        let tasks_path = directory.path().join("tasks.md");
        fs::write(&tasks_path, &rendered.markdown)
            .with_context(|| format!("failed to write {}", tasks_path.display()))?;
        write_json(&directory.path().join("manifest.json"), &rendered.manifest)?;
        write_json(&directory.path().join("baseline.json"), &rendered.baseline)?;
        fs::create_dir(directory.path().join("transactions")).with_context(|| {
            format!(
                "failed to create transaction directory below {}",
                directory.path().display()
            )
        })?;

        Ok(Self {
            directory,
            tasks_path,
        })
    }
}

fn session_parent() -> (PathBuf, bool) {
    match env::var_os("XDG_RUNTIME_DIR") {
        Some(runtime_dir) => (PathBuf::from(runtime_dir).join("todomd"), true),
        None => (env::temp_dir(), false),
    }
}

pub fn load_from_tasks_path(tasks_path: &Path) -> Result<Option<LoadedSession>> {
    if tasks_path.file_name().and_then(|name| name.to_str()) != Some("tasks.md") {
        return Ok(None);
    }
    let Some(root) = tasks_path.parent() else {
        return Ok(None);
    };
    if !root.join("live.json").is_file() {
        return Ok(None);
    }
    load(root).map(Some)
}

pub fn load(root: &Path) -> Result<LoadedSession> {
    validate_root(root)?;
    // Keep the historical filename compatible with version-3 sessions.
    let metadata_path = root.join("live.json");
    let metadata: SessionMetadata = read_json(&metadata_path)
        .with_context(|| "session format is incompatible; recreate it with this todomd version")?;
    if metadata.format_version != SESSION_FORMAT_VERSION {
        anyhow::bail!(
            "session format {} is incompatible; recreate it with this todomd version",
            metadata.format_version
        );
    }
    let loaded = LoadedSession {
        root: root.to_path_buf(),
        metadata,
        manifest: read_json(&root.join("manifest.json"))?,
        baseline: read_json(&root.join("baseline.json"))?,
        recovery_baseline: read_json(&root.join("recovery-baseline.json"))?,
        accepted_text: fs::read_to_string(root.join("accepted.md")).with_context(|| {
            format!(
                "failed to read accepted live document in {}",
                root.display()
            )
        })?,
    };
    Ok(loaded)
}

pub struct SessionLock {
    _file: File,
}

pub fn lock(root: &Path) -> Result<SessionLock> {
    let path = root.join(".lock");
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&path)
        .with_context(|| format!("failed to open session lock {}", path.display()))?;
    FileExt::try_lock_exclusive(&file)
        .with_context(|| format!("session {} is already in use", root.display()))?;
    Ok(SessionLock { _file: file })
}

pub fn validate_root(root: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(root)
        .with_context(|| format!("failed to inspect session {}", root.display()))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        bail!("session {} is not a directory", root.display());
    }
    let name = root
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("");
    if !name.starts_with("session-") {
        bail!("session directory name must start with 'session-'");
    }
    let marker_path = root.join(".todomd-session");
    let marker = fs::read(&marker_path)
        .with_context(|| format!("{} is not a todomd session", root.display()))?;
    if marker != SESSION_MARKER {
        bail!("{} is not a todomd session", root.display());
    }
    Ok(())
}

pub fn mark_attached(root: &Path) -> Result<()> {
    fs::write(root.join("attached"), b"")
        .with_context(|| format!("failed to attach live session {}", root.display()))
}

pub fn close_live(root: &Path, accepted_text: &str, current_text: &str) -> Result<bool> {
    let unaccepted = current_text != accepted_text;
    if unaccepted {
        write_atomic(&root.join("unaccepted.md"), current_text.as_bytes())?;
    }
    write_atomic(&root.join("tasks.md"), accepted_text.as_bytes())?;
    Ok(unaccepted)
}

pub fn change_live_view(root: &Path, metadata: &SessionMetadata, markdown: &str) -> Result<()> {
    let metadata_path = root.join("live.json");
    replace_artifacts([
        (metadata_path.clone(), json_bytes(&metadata_path, metadata)?),
        (root.join("accepted.md"), markdown.as_bytes().to_vec()),
    ])
}

pub fn render_accepted(
    view: &View,
    manifest: &IdentityManifest,
    baseline: TaskState,
    recovery_baseline: TaskState,
) -> Result<AcceptedState> {
    let mut manifest = manifest.clone();
    let text = markdown::render_with_view(&baseline, view, &mut manifest)?;
    Ok(AcceptedState {
        text,
        manifest,
        baseline,
        recovery_baseline,
    })
}

pub fn persist_accepted(
    root: &Path,
    accepted: &AcceptedState,
    tasks_update: TasksUpdate,
) -> Result<()> {
    let AcceptedState {
        text,
        manifest,
        baseline,
        recovery_baseline,
    } = accepted;
    let baseline_path = root.join("baseline.json");
    let manifest_path = root.join("manifest.json");
    let recovery_path = root.join("recovery-baseline.json");
    let mut artifacts = vec![
        (baseline_path.clone(), json_bytes(&baseline_path, baseline)?),
        (manifest_path.clone(), json_bytes(&manifest_path, manifest)?),
        (
            recovery_path.clone(),
            json_bytes(&recovery_path, recovery_baseline)?,
        ),
        (root.join("accepted.md"), text.as_bytes().to_vec()),
    ];
    if tasks_update == TasksUpdate::ReplaceFile {
        artifacts.push((root.join("tasks.md"), text.as_bytes().to_vec()));
    }
    replace_artifacts(artifacts)
}

fn write_json(path: &Path, value: &impl Serialize) -> Result<()> {
    let contents = json_bytes(path, value)?;
    fs::write(path, contents).with_context(|| format!("failed to write {}", path.display()))
}

fn read_json<T: DeserializeOwned>(path: &Path) -> Result<T> {
    let contents = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&contents).with_context(|| format!("failed to parse {}", path.display()))
}

fn write_atomic(path: &Path, contents: &[u8]) -> Result<()> {
    persist_atomic(prepare_atomic(path, contents)?, path)
}

fn json_bytes(path: &Path, value: &impl Serialize) -> Result<Vec<u8>> {
    let mut contents = serde_json::to_vec_pretty(value)
        .with_context(|| format!("failed to serialize {}", path.display()))?;
    contents.push(b'\n');
    Ok(contents)
}

fn prepare_atomic(path: &Path, contents: &[u8]) -> Result<NamedTempFile> {
    let parent = path
        .parent()
        .context("session file has no parent directory")?;
    let mut temporary = NamedTempFile::new_in(parent)
        .with_context(|| format!("failed to create temporary file in {}", parent.display()))?;
    temporary
        .write_all(contents)
        .with_context(|| format!("failed to write temporary file for {}", path.display()))?;
    temporary
        .as_file()
        .sync_all()
        .with_context(|| format!("failed to sync temporary file for {}", path.display()))?;
    Ok(temporary)
}

fn persist_atomic(temporary: NamedTempFile, path: &Path) -> Result<()> {
    temporary
        .persist(path)
        .map_err(|error| error.error)
        .with_context(|| format!("failed to replace {}", path.display()))?;
    Ok(())
}

struct PreparedReplacement {
    path: PathBuf,
    replacement: NamedTempFile,
    rollback: NamedTempFile,
}

fn replace_artifacts(artifacts: impl IntoIterator<Item = (PathBuf, Vec<u8>)>) -> Result<()> {
    let replacements = artifacts
        .into_iter()
        .map(|(path, contents)| {
            Ok(PreparedReplacement {
                rollback: prepare_atomic(&path, &fs::read(&path)?)?,
                replacement: prepare_atomic(&path, &contents)?,
                path,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    persist_replacements(replacements)
}

fn persist_replacements(replacements: Vec<PreparedReplacement>) -> Result<()> {
    let mut rollbacks = Vec::new();
    for replacement in replacements {
        if let Err(error) = persist_atomic(replacement.replacement, &replacement.path) {
            return if rollbacks.is_empty() {
                Err(error)
            } else {
                Err(rollback_replacements(error, rollbacks))
            };
        }
        rollbacks.push((replacement.rollback, replacement.path));
    }
    Ok(())
}

fn rollback_replacements(original: Error, replacements: Vec<(NamedTempFile, PathBuf)>) -> Error {
    let errors = replacements
        .into_iter()
        .rev()
        .filter_map(|(temporary, path)| persist_atomic(temporary, &path).err())
        .map(|error| format!("{error:#}"))
        .collect::<Vec<_>>();
    if errors.is_empty() {
        original.context("session refresh failed; replaced artifacts were rolled back")
    } else {
        anyhow!(
            "session refresh failed: {original:#}; artifact rollback also failed: {}",
            errors.join("; ")
        )
    }
}

#[cfg(unix)]
fn create_private_directory(path: &Path) -> Result<()> {
    use std::os::unix::fs::DirBuilderExt;

    let mut builder = fs::DirBuilder::new();
    builder.recursive(true).mode(0o700);
    builder
        .create(path)
        .with_context(|| format!("failed to create private directory {}", path.display()))?;

    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("failed to inspect private directory {}", path.display()))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        anyhow::bail!(
            "private session parent {} is not a directory",
            path.display()
        );
    }
    restrict_directory(path)
}

#[cfg(not(unix))]
fn create_private_directory(path: &Path) -> Result<()> {
    fs::create_dir_all(path)
        .with_context(|| format!("failed to create private directory {}", path.display()))
}

#[cfg(unix)]
fn restrict_directory(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;

    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        .with_context(|| format!("failed to restrict permissions on {}", path.display()))
}

#[cfg(not(unix))]
fn restrict_directory(_path: &Path) -> Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::{model::TaskState, repository::SourceSnapshot};

    use super::super::markdown::IdentityManifest;

    use super::*;

    #[cfg(unix)]
    #[test]
    fn creates_a_restricted_private_parent() {
        use std::os::unix::fs::PermissionsExt;

        let root = tempfile::tempdir().unwrap();
        let parent = root.path().join("nested/todomd");
        create_private_directory(&parent).unwrap();

        let mode = fs::metadata(parent).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o700);
    }

    #[test]
    fn restores_prior_artifacts_after_each_replacement_failure() {
        for failure_index in 0..4 {
            let directory = tempfile::tempdir().unwrap();
            let paths = (0..4)
                .map(|index| directory.path().join(format!("artifact-{index}")))
                .collect::<Vec<_>>();
            let replacements = paths
                .iter()
                .map(|path| {
                    fs::write(path, "old").unwrap();
                    PreparedReplacement {
                        path: path.clone(),
                        replacement: prepare_atomic(path, b"new").unwrap(),
                        rollback: prepare_atomic(path, b"old").unwrap(),
                    }
                })
                .collect();
            fs::remove_file(&paths[failure_index]).unwrap();
            fs::create_dir(&paths[failure_index]).unwrap();

            let error = persist_replacements(replacements).unwrap_err();
            let message = format!("{error:#}");

            assert!(message.contains("failed to replace"));
            assert_eq!(message.contains("were rolled back"), failure_index > 0);
            for (index, path) in paths.iter().enumerate() {
                if index != failure_index {
                    assert_eq!(fs::read_to_string(path).unwrap(), "old");
                }
            }
        }
    }

    #[test]
    fn atomically_records_an_accepted_state_in_each_tasks_mode() {
        use crate::model::{Priority, Task, TaskId, TaskList};

        let parent = tempfile::tempdir().unwrap();
        let rendered = RenderedSession {
            markdown: "# Personal\n".into(),
            manifest: IdentityManifest::default(),
            baseline: TaskState { lists: Vec::new() },
            sources: SourceSnapshot::default(),
        };
        let session = Session::create_in(parent.path(), &rendered).unwrap();
        fs::write(session.path().join("recovery-baseline.json"), b"null").unwrap();
        fs::write(session.path().join("accepted.md"), &rendered.markdown).unwrap();
        let state = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("new@example.test"),
                    summary: "Accepted".into(),
                    completed: false,
                    priority: Priority::None,
                    categories: vec![],
                    parent: None,
                    start: None,
                    due: None,
                }],
            }],
        };
        let accepted = render_accepted(
            &View::default(),
            &IdentityManifest::default(),
            state.clone(),
            state.clone(),
        )
        .unwrap();

        persist_accepted(session.path(), &accepted, TasksUpdate::EditorManaged).unwrap();

        assert_eq!(
            fs::read_to_string(session.path().join("accepted.md")).unwrap(),
            accepted.text
        );
        assert_eq!(
            fs::read_to_string(session.path().join("tasks.md")).unwrap(),
            rendered.markdown
        );

        persist_accepted(session.path(), &accepted, TasksUpdate::ReplaceFile).unwrap();
        assert_eq!(
            fs::read_to_string(session.path().join("tasks.md")).unwrap(),
            accepted.text
        );

        let stored_recovery: TaskState = serde_json::from_slice(
            &fs::read(session.path().join("recovery-baseline.json")).unwrap(),
        )
        .unwrap();
        assert_eq!(stored_recovery, state);
        let stored_baseline: TaskState =
            serde_json::from_slice(&fs::read(session.path().join("baseline.json")).unwrap())
                .unwrap();
        let stored_manifest: IdentityManifest =
            serde_json::from_slice(&fs::read(session.path().join("manifest.json")).unwrap())
                .unwrap();
        assert_eq!(stored_baseline, state);
        assert_eq!(stored_manifest, accepted.manifest);
    }

    #[test]
    fn creates_and_retains_session_artifacts() {
        let parent = tempfile::tempdir().unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(parent.path(), fs::Permissions::from_mode(0o755)).unwrap();
        }
        let rendered = RenderedSession {
            markdown: "# Personal\n".into(),
            manifest: IdentityManifest::default(),
            baseline: TaskState { lists: Vec::new() },
            sources: SourceSnapshot::default(),
        };
        let session = Session::create_in(parent.path(), &rendered).unwrap();

        assert_eq!(
            fs::read_to_string(session.tasks_path()).unwrap(),
            "# Personal\n"
        );
        assert!(session.directory.path().join("manifest.json").is_file());
        assert!(session.directory.path().join("baseline.json").is_file());
        assert!(session.directory.path().join("transactions").is_dir());

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(session.directory.path())
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o700);
            let parent_mode = fs::metadata(parent.path()).unwrap().permissions().mode();
            assert_eq!(parent_mode & 0o777, 0o755);
        }

        let retained = session.retain();
        assert!(retained.is_dir());
    }
}
