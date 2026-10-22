---
name: nix-shell
description: Use `nix-shell` for ephemeral environments and one-off commands without installing packages globally. Load this skill whenever you're missing a package, command, or module. "command not found" in bash, "ModuleNotFoundError" in python, etc.
---

## Choose the environment

| Need | Use |
| --- | --- |
| Dependencies already available | Run the command directly |
| Missing executable | `nix-shell -p <package> --run '<executable> [args...]'` |
| Missing Python import | `python3.withPackages` recipe below |
| Several tools or a pipeline | `nix-shell -p <package1> <package2> --run '...'` |

Keep one-offs ephemeral: no global installs or profile changes. Always use
`--run`; don't open an interactive shell in an agent run.

Packages resolve through `<nixpkgs>` via `NIX_PATH`; on this setup it points to
`flake:nixpkgs`, using the registry's nixpkgs.

## Shell syntax and quoting

`nix-shell --run` takes a single string of Bash code, not separate executable
arguments. Quote the command and its arguments at the appropriate level:

```bash
nix-shell -p jq --run 'jq -r ".name" "data file.json"'
```

Your outer shell processes unquoted pipes, redirects, variables, and globs before
Nix runs. A redirect such as `> result.txt` can stay outside; commands that need
the added tools must run inside. Put pipelines, `cd`, loops, or expansion inside
the quoted command when they need the environment:

```bash
nix-shell -p curl jq --run \
  'set -euo pipefail; curl -fsSL https://example.com/a.json | jq -r .name' > result.txt
```

`pipefail` propagates a failing pipeline stage instead of hiding it behind a
successful final command. Pass dynamic values through environment variables
rather than interpolating them into shell code:

```bash
INPUT_FILE='data file.json' nix-shell -p jq --run 'jq -r .name "$INPUT_FILE"'
```

## Python imports

Compose an interpreter with `python3.withPackages` rather than adding an
interpreter and Python library packages separately:

```bash
nix-shell -p 'python3.withPackages (ps: [ ps.requests ps.pyyaml ])' \
  --run 'python3 job.py'
```

For inline Python, feed a quoted heredoc to `python3 -` through stdin. Quoting
`EOF` prevents the outer shell from expanding variables or substitutions in the
Python code:

```bash
nix-shell -p 'python3.withPackages (ps: [ ps.pyyaml ])' --run 'python3 -' <<'EOF'
import yaml

print(yaml.safe_load("message: hello from Python")["message"])
EOF
```

Replace the package list as needed; import names may differ from Nix attributes
(`yaml` → `pyyaml`, `bs4` → `beautifulsoup4`). Add other tools to the same
invocation when needed:

```bash
nix-shell -p 'python3.withPackages (ps: [ ps.requests ])' jq \
  --run 'set -euo pipefail; python3 job.py | jq .'
```

## Package names

Package attributes and executable names need not match:

```bash
nix-shell -p ripgrep --run 'rg "pattern" .'
```

If an attribute is unknown, look it up with `nix search nixpkgs <query>`.
