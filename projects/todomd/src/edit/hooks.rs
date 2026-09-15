use std::{
    process::Command,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use anyhow::{Context, Result, bail};

use crate::config::Hooks;

#[derive(Clone)]
pub struct Lifecycle {
    hooks: Hooks,
}

impl Lifecycle {
    pub fn live(hooks: &Hooks, enabled: bool) -> Self {
        Self {
            hooks: if enabled {
                hooks.clone()
            } else {
                Hooks::default()
            },
        }
    }

    pub fn has_after_apply(&self) -> bool {
        self.hooks.after_apply.is_some()
    }

    pub fn after_apply(&self) -> Result<()> {
        run_hook("after_apply", self.hooks.after_apply.as_deref())
    }
}

pub struct Termination {
    requested: Arc<AtomicBool>,
}

impl Termination {
    pub fn install() -> Result<Self> {
        let requested = Arc::new(AtomicBool::new(false));
        #[cfg(unix)]
        for signal in [
            signal_hook::consts::SIGINT,
            signal_hook::consts::SIGTERM,
            signal_hook::consts::SIGHUP,
        ] {
            signal_hook::flag::register_conditional_default(signal, Arc::clone(&requested))
                .with_context(|| format!("failed to install handler for signal {signal}"))?;
            signal_hook::flag::register(signal, Arc::clone(&requested))
                .with_context(|| format!("failed to install handler for signal {signal}"))?;
        }
        Ok(Self { requested })
    }

    pub fn is_requested(&self) -> bool {
        self.requested.load(Ordering::Relaxed)
    }

    pub fn check(&self) -> Result<()> {
        if self.is_requested() {
            bail!("termination requested");
        }
        Ok(())
    }
}

fn run_hook(name: &str, hook: Option<&[String]>) -> Result<()> {
    let Some((program, arguments)) = hook.and_then(|hook| hook.split_first()) else {
        return Ok(());
    };
    let status = Command::new(program)
        .args(arguments)
        .status()
        .with_context(|| format!("failed to start {name} hook program {program:?}"))?;
    if !status.success() {
        bail!("{name} hook exited unsuccessfully ({status})");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    #[cfg(unix)]
    fn append_hook(path: &std::path::Path, value: &str) -> Vec<String> {
        vec![
            "/bin/sh".into(),
            "-c".into(),
            "printf '%s\\n' \"$1\" >> \"$2\"".into(),
            "todomd-hook".into(),
            value.into(),
            path.to_string_lossy().into_owned(),
        ]
    }

    #[cfg(unix)]
    #[test]
    fn live_lifecycle_runs_after_apply() {
        let directory = tempfile::tempdir().unwrap();
        let log = directory.path().join("hooks.log");
        let hooks = Hooks {
            after_apply: Some(append_hook(&log, "apply")),
        };

        let lifecycle = Lifecycle::live(&hooks, true);
        lifecycle.after_apply().unwrap();

        assert_eq!(fs::read_to_string(log).unwrap(), "apply\n");
    }

    #[cfg(unix)]
    #[test]
    fn disabled_lifecycle_runs_no_hooks() {
        let directory = tempfile::tempdir().unwrap();
        let log = directory.path().join("hooks.log");
        let hooks = Hooks {
            after_apply: Some(append_hook(&log, "apply")),
        };

        let lifecycle = Lifecycle::live(&hooks, false);
        lifecycle.after_apply().unwrap();

        assert!(!log.exists());
    }
}
