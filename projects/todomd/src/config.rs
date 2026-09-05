use std::{
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use serde::Deserialize;

#[derive(Clone, Debug, Deserialize)]
pub struct Config {
    pub calendar_roots: Vec<PathBuf>,
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

        Ok(config)
    }

    pub fn new(calendar_roots: Vec<PathBuf>) -> Result<Self> {
        if calendar_roots.is_empty() {
            bail!("configuration must define at least one calendar root");
        }
        Ok(Self { calendar_roots })
    }
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
}
