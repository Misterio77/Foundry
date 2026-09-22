use std::time::{Duration, Instant};

use anyhow::{Result, bail};

use super::{editor, session::Session};

const ATTACH_TIMEOUT: Duration = Duration::from_secs(10);

pub fn run(session: Session, termination: &super::hooks::Termination) -> Result<()> {
    termination.check()?;
    let started = Instant::now();

    let result = editor::open(
        session.tasks_path(),
        || termination.is_requested(),
        || {
            if !session.is_attached() && started.elapsed() >= ATTACH_TIMEOUT {
                bail!(
                    "editor did not attach todomd lsp within {} seconds",
                    ATTACH_TIMEOUT.as_secs()
                );
            }
            Ok(())
        },
    );
    let result = result.and_then(|()| {
        termination.check()?;
        if !session.is_attached() {
            bail!("editor closed before todomd lsp attached");
        }
        Ok(())
    });

    let retained = session.retain();
    eprintln!("todomd: live session retained at {}", retained.display());
    result
}
