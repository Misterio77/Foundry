use std::{env, path::Path, process::Command};

use anyhow::{Context, Result, bail};

pub fn open(path: &Path) -> Result<()> {
    let command_line = editor_command()?;
    run(&command_line, path)
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

fn run(command_line: &str, path: &Path) -> Result<()> {
    let arguments = parse_command(command_line)?;
    let (program, editor_arguments) = arguments
        .split_first()
        .context("editor command cannot be empty")?;
    let status = Command::new(program)
        .args(editor_arguments)
        .arg(path)
        .status()
        .with_context(|| format!("failed to start editor {program:?}"))?;

    if !status.success() {
        bail!("editor exited with {status}");
    }

    Ok(())
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
