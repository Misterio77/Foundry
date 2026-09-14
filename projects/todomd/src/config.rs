use std::{
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Config {
    pub calendar_roots: Vec<PathBuf>,
    #[serde(default)]
    pub hooks: Hooks,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Hooks {
    pub before_session: Option<Vec<String>>,
    pub after_apply: Option<Vec<String>>,
    pub after_session: Option<Vec<String>>,
}

impl Config {
    pub fn load(path: Option<&Path>) -> Result<Self> {
        let path = match path {
            Some(path) => expand_home(path)?,
            None => default_path()?,
        };
        let contents = fs::read_to_string(&path)
            .with_context(|| format!("failed to read configuration {}", path.display()))?;
        let mut config: Self = toml::from_str(&contents)
            .with_context(|| format!("failed to parse configuration {}", path.display()))?;

        if config.calendar_roots.is_empty() {
            bail!("configuration must define at least one calendar root");
        }

        config.calendar_roots = config
            .calendar_roots
            .iter()
            .map(|root| expand_home(root))
            .collect::<Result<_>>()?;
        expand_hook(&mut config.hooks.before_session)?;
        expand_hook(&mut config.hooks.after_apply)?;
        expand_hook(&mut config.hooks.after_session)?;
        validate_hook("before_session", config.hooks.before_session.as_deref())?;
        validate_hook("after_apply", config.hooks.after_apply.as_deref())?;
        validate_hook("after_session", config.hooks.after_session.as_deref())?;

        Ok(config)
    }

    pub fn new(calendar_roots: Vec<PathBuf>) -> Result<Self> {
        if calendar_roots.is_empty() {
            bail!("configuration must define at least one calendar root");
        }
        Ok(Self {
            calendar_roots,
            hooks: Hooks::default(),
        })
    }
}

fn expand_hook(hook: &mut Option<Vec<String>>) -> Result<()> {
    let Some(arguments) = hook else {
        return Ok(());
    };
    for argument in arguments {
        let expanded = expand_home(Path::new(argument))?;
        *argument = expanded.to_string_lossy().into_owned();
    }
    Ok(())
}

fn validate_hook(name: &str, hook: Option<&[String]>) -> Result<()> {
    if let Some([]) = hook {
        bail!("{name} hook must contain a program");
    }
    if hook.is_some_and(|arguments| arguments[0].is_empty()) {
        bail!("{name} hook program must not be empty");
    }
    Ok(())
}

fn default_path() -> Result<PathBuf> {
    if let Some(config_home) = env::var_os("XDG_CONFIG_HOME") {
        return Ok(PathBuf::from(config_home).join("todomd/config.toml"));
    }

    Ok(home_dir()?.join(".config/todomd/config.toml"))
}

fn expand_home(path: &Path) -> Result<PathBuf> {
    if path == Path::new("~") {
        return home_dir();
    }

    if let Ok(rest) = path.strip_prefix("~/") {
        return Ok(home_dir()?.join(rest));
    }

    Ok(path.to_path_buf())
}

fn home_dir() -> Result<PathBuf> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .context("HOME is not set, so ~ cannot be expanded")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_roots() {
        assert!(Config::new(Vec::new()).is_err());
    }

    #[test]
    fn loads_hook_argument_arrays() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n\
             [hooks]\n\
             before_session = [\"program\", \"argument\"]\n",
        )
        .unwrap();

        let config = Config::load(Some(&path)).unwrap();
        assert_eq!(
            config.hooks.before_session,
            Some(vec!["program".into(), "argument".into()])
        );
        assert!(config.hooks.after_session.is_none());
    }

    #[test]
    fn rejects_empty_hook_arrays() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n[hooks]\nafter_session = []\n",
        )
        .unwrap();

        assert!(Config::load(Some(&path)).is_err());
    }
}
