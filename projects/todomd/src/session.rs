use std::{
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use serde::Serialize;
use tempfile::{Builder, TempDir};

use crate::RenderedSession;

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
    let mut contents = serde_json::to_vec_pretty(value)
        .with_context(|| format!("failed to serialize {}", path.display()))?;
    contents.push(b'\n');
    fs::write(path, contents).with_context(|| format!("failed to write {}", path.display()))
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
    use crate::{markdown::IdentityManifest, model::TaskState, repository::SourceSnapshot};

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
