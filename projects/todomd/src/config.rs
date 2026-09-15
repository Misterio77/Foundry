use std::{
    collections::{BTreeMap, BTreeSet},
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Config {
    pub calendar_roots: Vec<PathBuf>,
    #[serde(default)]
    pub sorting: Sorting,
    #[serde(default)]
    pub hooks: Hooks,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SortKey {
    Completed,
    Manual,
    Due,
    Start,
    Priority,
    Summary,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Sorting {
    #[serde(default = "default_sort_keys")]
    pub default: Vec<SortKey>,
    #[serde(default)]
    pub lists: BTreeMap<String, Vec<SortKey>>,
}

impl Default for Sorting {
    fn default() -> Self {
        Self {
            default: default_sort_keys(),
            lists: BTreeMap::new(),
        }
    }
}

impl Sorting {
    pub fn for_list(&self, name: &str) -> &[SortKey] {
        self.lists.get(name).unwrap_or(&self.default)
    }

    fn validate(&self) -> Result<()> {
        validate_sort_keys("sorting.default", &self.default)?;
        for (name, keys) in &self.lists {
            validate_sort_keys(&format!("sorting.lists.{name}"), keys)?;
        }
        Ok(())
    }
}

fn default_sort_keys() -> Vec<SortKey> {
    vec![SortKey::Completed, SortKey::Priority, SortKey::Summary]
}

fn validate_sort_keys(name: &str, keys: &[SortKey]) -> Result<()> {
    if keys.is_empty() {
        bail!("{name} must contain at least one sort key");
    }
    if keys.iter().collect::<BTreeSet<_>>().len() != keys.len() {
        bail!("{name} must not contain duplicate sort keys");
    }
    Ok(())
}

/// Unknown keys are rejected so a removed session-lifetime hook is reported
/// rather than silently ignored.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Hooks {
    pub after_apply: Option<Vec<String>>,
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
        config.sorting.validate()?;
        expand_hook(&mut config.hooks.after_apply)?;
        validate_hook("after_apply", config.hooks.after_apply.as_deref())?;

        Ok(config)
    }

    pub fn new(calendar_roots: Vec<PathBuf>) -> Result<Self> {
        if calendar_roots.is_empty() {
            bail!("configuration must define at least one calendar root");
        }
        Ok(Self {
            calendar_roots,
            sorting: Sorting::default(),
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
    fn loads_sorting_with_per_list_overrides() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n\
             [sorting]\n\
             default = [\"due\", \"priority\", \"summary\"]\n\
             [sorting.lists]\n\
             Postgrad = [\"manual\", \"completed\"]\n",
        )
        .unwrap();

        let config = Config::load(Some(&path)).unwrap();
        assert_eq!(
            config.sorting.default,
            [SortKey::Due, SortKey::Priority, SortKey::Summary]
        );
        assert_eq!(
            config.sorting.for_list("Postgrad"),
            [SortKey::Manual, SortKey::Completed]
        );
        assert_eq!(
            config.sorting.for_list("Personal"),
            [SortKey::Due, SortKey::Priority, SortKey::Summary]
        );
    }

    #[test]
    fn rejects_empty_or_duplicate_sorting() {
        for sorting in [
            "[sorting]\ndefault = []\n",
            "[sorting]\ndefault = [\"summary\", \"summary\"]\n",
            "[sorting.lists]\nWork = []\n",
        ] {
            let directory = tempfile::tempdir().unwrap();
            let path = directory.path().join("config.toml");
            fs::write(
                &path,
                format!("calendar_roots = [\"/tmp/calendars\"]\n{sorting}"),
            )
            .unwrap();

            assert!(Config::load(Some(&path)).is_err());
        }
    }

    #[test]
    fn loads_hook_argument_arrays() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n\
             [hooks]\n\
             after_apply = [\"program\", \"argument\"]\n",
        )
        .unwrap();

        let config = Config::load(Some(&path)).unwrap();
        assert_eq!(
            config.hooks.after_apply,
            Some(vec!["program".into(), "argument".into()])
        );
    }

    #[test]
    fn rejects_hooks_that_no_longer_exist() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n\
             [hooks]\n\
             before_session = [\"program\"]\n",
        )
        .unwrap();

        let error = Config::load(Some(&path)).unwrap_err();

        assert!(format!("{error:#}").contains("before_session"));
    }

    #[test]
    fn rejects_empty_hook_arrays() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n[hooks]\nafter_apply = []\n",
        )
        .unwrap();

        assert!(Config::load(Some(&path)).is_err());
    }
}
