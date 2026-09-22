use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::view::View;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub calendar_roots: Vec<PathBuf>,
    #[serde(default = "default_view_name")]
    pub default_view: String,
    #[serde(default)]
    pub views: BTreeMap<String, View>,
    #[serde(default)]
    pub hooks: Hooks,
}

fn default_view_name() -> String {
    "default".into()
}

/// Unknown keys are rejected so removed configuration is reported rather than
/// silently ignored.
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
        let mut config: Self = toml::from_str(&contents).map_err(|error| {
            let error = anyhow::Error::new(error)
                .context(format!("failed to parse configuration {}", path.display()));
            if contents
                .lines()
                .any(|line| line.trim().starts_with("[sorting"))
            {
                error.context(
                    "[sorting] was replaced by named [views.NAME] with group_by and sort_by",
                )
            } else {
                error
            }
        })?;

        if config.calendar_roots.is_empty() {
            bail!("configuration must define at least one calendar root");
        }

        config.calendar_roots = config
            .calendar_roots
            .iter()
            .map(|root| expand_home(root))
            .collect::<Result<_>>()?;
        config.validate_views()?;
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
            default_view: default_view_name(),
            views: BTreeMap::new(),
            hooks: Hooks::default(),
        })
    }

    pub fn view(&self, name: Option<&str>) -> Result<View> {
        let name = name.unwrap_or(&self.default_view);
        match self.views.get(name) {
            Some(view) => Ok(view.clone()),
            None if name == "default" => Ok(View::default()),
            None => bail!("unknown view {name:?}"),
        }
    }

    pub fn view_names(&self) -> Vec<String> {
        let mut names = self.views.keys().cloned().collect::<Vec<_>>();
        if !self.views.contains_key("default") {
            names.insert(0, "default".into());
        }
        names
    }

    fn validate_views(&self) -> Result<()> {
        for (name, view) in &self.views {
            view.validate(&format!("views.{name}"))?;
        }
        self.view(None)?;
        Ok(())
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
    use crate::view::{GroupKey, SortKey};

    #[test]
    fn rejects_empty_roots() {
        assert!(Config::new(Vec::new()).is_err());
    }

    #[test]
    fn loads_named_views() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n\
             default_view = \"agenda\"\n\
             [views.agenda]\n\
             group_by = [\"due\"]\n\
             sort_by = [\"due\", \"priority\", \"summary\"]\n",
        )
        .unwrap();

        let config = Config::load(Some(&path)).unwrap();
        let view = config.view(None).unwrap();
        assert_eq!(view.group_by, [GroupKey::Due]);
        assert_eq!(
            view.sort_by,
            [SortKey::Due, SortKey::Priority, SortKey::Summary]
        );
    }

    #[test]
    fn supplies_the_builtin_default() {
        let config = Config::new(vec!["/tmp/calendars".into()]).unwrap();
        assert_eq!(config.view(None).unwrap(), View::default());
        assert_eq!(config.view_names(), ["default"]);
    }

    #[test]
    fn rejects_invalid_views() {
        for contents in [
            "default_view = \"missing\"\n",
            "[views.bad]\ngroup_by = []\nsort_by = []\n",
            "[views.bad]\ngroup_by = [\"list\", \"list\"]\nsort_by = [\"summary\"]\n",
        ] {
            let directory = tempfile::tempdir().unwrap();
            let path = directory.path().join("config.toml");
            fs::write(
                &path,
                format!("calendar_roots = [\"/tmp/calendars\"]\n{contents}"),
            )
            .unwrap();

            assert!(Config::load(Some(&path)).is_err());
        }
    }

    #[test]
    fn explains_the_old_sorting_migration() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("config.toml");
        fs::write(
            &path,
            "calendar_roots = [\"/tmp/calendars\"]\n[sorting]\ndefault = [\"summary\"]\n",
        )
        .unwrap();

        let error = Config::load(Some(&path)).unwrap_err();
        assert!(format!("{error:#}").contains("replaced by named [views.NAME]"));
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
