use std::{env, path::Path, process::Command, thread, time::Duration};

use anyhow::{Context, Result, bail};

/// Opens the session document, polling `on_wait` while the editor runs.
pub fn open(
    path: &Path,
    interrupted: impl Fn() -> bool,
    on_wait: impl FnMut() -> Result<()>,
) -> Result<()> {
    let command_line = editor_command()?;
    run(&command_line, path, interrupted, on_wait)
}

fn editor_command() -> Result<String> {
    for variable in ["VISUAL", "EDITOR"] {
        if let Ok(value) = env::var(variable)
            && !value.trim().is_empty()
        {
            return Ok(value);
        }
    }

    bail!("neither VISUAL nor EDITOR names an editor")
}

fn run(
    command_line: &str,
    path: &Path,
    interrupted: impl Fn() -> bool,
    mut on_wait: impl FnMut() -> Result<()>,
) -> Result<()> {
    let arguments = parse_command(command_line)?;
    let (program, editor_arguments) = arguments
        .split_first()
        .context("editor command cannot be empty")?;
    let mut child = Command::new(program)
        .args(editor_arguments)
        .arg(path)
        .spawn()
        .with_context(|| format!("failed to start editor {program:?}"))?;

    loop {
        if let Some(status) = child
            .try_wait()
            .with_context(|| format!("failed to wait for editor {program:?}"))?
        {
            if !status.success() {
                bail!("editor exited with {status}");
            }
            return Ok(());
        }
        if interrupted() {
            child
                .kill()
                .with_context(|| format!("failed to stop editor {program:?}"))?;
            let _ = child.wait();
            bail!("termination requested");
        }
        if let Err(error) = on_wait() {
            child
                .kill()
                .with_context(|| format!("failed to stop editor {program:?}"))?;
            let _ = child.wait();
            return Err(error);
        }
        thread::sleep(Duration::from_millis(50));
    }
}

fn parse_command(command_line: &str) -> Result<Vec<String>> {
    shlex::split(command_line).context("editor command contains invalid shell quoting")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_editor_arguments_without_a_shell() {
        assert_eq!(
            parse_command("code --wait 'profile tasks'").unwrap(),
            ["code", "--wait", "profile tasks"]
        );
    }

    #[test]
    fn rejects_invalid_editor_quoting() {
        assert!(parse_command("editor '").is_err());
    }
}
