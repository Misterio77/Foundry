use std::{
    process::Command,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};

use anyhow::{Context, Result, anyhow, bail};

use crate::config::Hooks;

pub struct Lifecycle {
    hooks: Hooks,
    active: bool,
}

impl Lifecycle {
    pub fn start(hooks: &Hooks, enabled: bool) -> Result<Self> {
        if !enabled {
            return Ok(Self {
                hooks: Hooks::default(),
                active: false,
            });
        }

        run_hook("before_session", hooks.before_session.as_deref())?;
        Ok(Self {
            hooks: hooks.clone(),
            active: true,
        })
    }

    pub fn after_apply(&self) -> Result<()> {
        run_hook("after_apply", self.hooks.after_apply.as_deref())
    }

    pub fn finish<T>(mut self, result: Result<T>) -> Result<T> {
        let cleanup = if self.active {
            run_hook("after_session", self.hooks.after_session.as_deref())
        } else {
            Ok(())
        };
        self.active = false;
        match (result, cleanup) {
            (Ok(value), Ok(())) => Ok(value),
            (Err(error), Ok(())) => Err(error),
            (Ok(_), Err(cleanup)) => Err(cleanup),
            (Err(error), Err(cleanup)) => Err(anyhow!(
                "{error:#}; after_session hook also failed: {cleanup:#}"
            )),
        }
    }
}

impl Drop for Lifecycle {
    fn drop(&mut self) {
        if self.active {
            if let Err(error) = run_hook("after_session", self.hooks.after_session.as_deref()) {
                eprintln!("todomd: after_session hook failed during cleanup: {error:#}");
            }
            self.active = false;
        }
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
    fn runs_hooks_in_lifecycle_order() {
        let directory = tempfile::tempdir().unwrap();
        let log = directory.path().join("hooks.log");
        let hooks = Hooks {
            before_session: Some(append_hook(&log, "before")),
            after_apply: Some(append_hook(&log, "apply")),
            after_session: Some(append_hook(&log, "after")),
        };

        let lifecycle = Lifecycle::start(&hooks, true).unwrap();
        lifecycle.after_apply().unwrap();
        lifecycle.finish(Ok(())).unwrap();

        assert_eq!(fs::read_to_string(log).unwrap(), "before\napply\nafter\n");
    }

    #[cfg(unix)]
    #[test]
    fn disabled_lifecycle_runs_no_hooks() {
        let directory = tempfile::tempdir().unwrap();
        let log = directory.path().join("hooks.log");
        let hooks = Hooks {
            before_session: Some(append_hook(&log, "before")),
            after_apply: Some(append_hook(&log, "apply")),
            after_session: Some(append_hook(&log, "after")),
        };

        let lifecycle = Lifecycle::start(&hooks, false).unwrap();
        lifecycle.after_apply().unwrap();
        lifecycle.finish(Ok(())).unwrap();

        assert!(!log.exists());
    }

    #[cfg(unix)]
    #[test]
    fn skips_after_session_when_before_session_fails() {
        let directory = tempfile::tempdir().unwrap();
        let log = directory.path().join("hooks.log");
        let hooks = Hooks {
            before_session: Some(vec!["/bin/false".into()]),
            after_apply: None,
            after_session: Some(append_hook(&log, "after")),
        };

        assert!(Lifecycle::start(&hooks, true).is_err());
        assert!(!log.exists());
    }

    #[cfg(unix)]
    #[test]
    fn after_session_failure_does_not_hide_primary_failure() {
        let hooks = Hooks {
            before_session: None,
            after_apply: None,
            after_session: Some(vec!["/bin/false".into()]),
        };
        let lifecycle = Lifecycle::start(&hooks, true).unwrap();
        let error = lifecycle
            .finish::<()>(Err(anyhow!("primary failure")))
            .unwrap_err();

        let message = format!("{error:#}");
        assert!(message.contains("primary failure"));
        assert!(message.contains("after_session hook also failed"));
    }
}
