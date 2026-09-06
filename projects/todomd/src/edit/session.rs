use std::{
    env, fs,
    io::Write,
    path::{Path, PathBuf},
};

use anyhow::{Context, Error, Result, anyhow};
use serde::Serialize;
use tempfile::{Builder, NamedTempFile, TempDir};

use super::{RenderedSession, markdown::IdentityManifest};
use crate::model::TaskState;

#[derive(Debug)]
pub struct Session {
    directory: TempDir,
    tasks_path: PathBuf,
}

impl Session {
    pub fn create(rendered: &RenderedSession) -> Result<Self> {
        let (parent, is_private_parent) = session_parent();
        if is_private_parent {
            create_private_directory(&parent)?;
        }
        Self::create_in(&parent, rendered)
    }

    pub fn path(&self) -> &Path {
        self.directory.path()
    }

    pub fn tasks_path(&self) -> &Path {
        &self.tasks_path
    }

    pub fn read_tasks(&self) -> Result<String> {
        fs::read_to_string(&self.tasks_path)
            .with_context(|| format!("failed to read {}", self.tasks_path.display()))
    }

    pub fn accept(
        &self,
        markdown: &str,
        manifest: &IdentityManifest,
        baseline: &TaskState,
    ) -> Result<()> {
        let baseline_path = self.directory.path().join("baseline.json");
        let manifest_path = self.directory.path().join("manifest.json");
        let old_baseline = fs::read(&baseline_path)
            .with_context(|| format!("failed to read {}", baseline_path.display()))?;
        let old_manifest = fs::read(&manifest_path)
            .with_context(|| format!("failed to read {}", manifest_path.display()))?;
        let baseline_rollback = prepare_atomic(&baseline_path, &old_baseline)?;
        let manifest_rollback = prepare_atomic(&manifest_path, &old_manifest)?;
        let baseline = prepare_atomic(&baseline_path, &json_bytes(&baseline_path, baseline)?)?;
        let manifest = prepare_atomic(&manifest_path, &json_bytes(&manifest_path, manifest)?)?;
        let tasks = prepare_atomic(&self.tasks_path, markdown.as_bytes())?;

        persist_atomic(baseline, &baseline_path)?;
        if let Err(error) = persist_atomic(manifest, &manifest_path) {
            return Err(rollback_replacements(
                error,
                [(baseline_rollback, baseline_path.as_path())],
            ));
        }
        if let Err(error) = persist_atomic(tasks, &self.tasks_path) {
            return Err(rollback_replacements(
                error,
                [
                    (manifest_rollback, manifest_path.as_path()),
                    (baseline_rollback, baseline_path.as_path()),
                ],
            ));
        }
        Ok(())
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

fn write_json(path: &Path, value: &impl Serialize) -> Result<()> {
    let contents = json_bytes(path, value)?;
    fs::write(path, contents).with_context(|| format!("failed to write {}", path.display()))
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

fn rollback_replacements<const N: usize>(
    original: Error,
    replacements: [(NamedTempFile, &Path); N],
) -> Error {
    let errors = replacements
        .into_iter()
        .filter_map(|(temporary, path)| persist_atomic(temporary, path).err())
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
    fn restores_replaced_artifacts_after_a_refresh_failure() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("baseline.json");
        fs::write(&path, "old").unwrap();
        let rollback = prepare_atomic(&path, b"old").unwrap();
        fs::write(&path, "new").unwrap();

        let error = rollback_replacements(
            anyhow!("later replacement failed"),
            [(rollback, path.as_path())],
        );

        assert!(format!("{error:#}").contains("were rolled back"));
        assert_eq!(fs::read_to_string(path).unwrap(), "old");
    }

    #[test]
    fn atomically_records_an_accepted_state() {
        use crate::model::{Priority, Task, TaskId, TaskList};

        let parent = tempfile::tempdir().unwrap();
        let rendered = RenderedSession {
            markdown: "# Personal\n".into(),
            manifest: IdentityManifest::default(),
            baseline: TaskState { lists: Vec::new() },
            sources: SourceSnapshot::default(),
        };
        let session = Session::create_in(parent.path(), &rendered).unwrap();
        let accepted = TaskState {
            lists: vec![TaskList {
                name: "Personal".into(),
                tasks: vec![Task {
                    id: TaskId::new("new@example.test"),
                    summary: "Accepted".into(),
                    completed: false,
                    priority: Priority::None,
                }],
            }],
        };
        let mut manifest = IdentityManifest::default();
        let markdown = super::super::markdown::render(&accepted, &mut manifest).unwrap();

        session.accept(&markdown, &manifest, &accepted).unwrap();

        assert_eq!(session.read_tasks().unwrap(), markdown);
        let stored_baseline: TaskState =
            serde_json::from_slice(&fs::read(session.path().join("baseline.json")).unwrap())
                .unwrap();
        let stored_manifest: IdentityManifest =
            serde_json::from_slice(&fs::read(session.path().join("manifest.json")).unwrap())
                .unwrap();
        assert_eq!(stored_baseline, accepted);
        assert_eq!(stored_manifest, manifest);
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
