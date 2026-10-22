---
name: nix-shell
description: Use `nix shell` for ephemeral environments and one-off commands without installing packages globally. Load this skill whenever you're missing a package, command, or module. "command not found" in bash, "ModuleNotFoundError" in python, etc.
---

## Choose the environment

| Need | Use |
| --- | --- |
| Dependencies already available | Run the command directly |
| Missing executable | `nix shell nixpkgs#<package> -c <executable> [args...]` |
| Missing Python import | `python3.withPackages` recipe below |
| Pipes, builtins, or shell expansion inside the environment | `nix shell ... -c bash -euo pipefail -c '...'` |
| One tool with a suitable default app | `nix run nixpkgs#<package> -- [args...]` |

Keep one-offs ephemeral: no global installs or profile changes. Don't open an
interactive shell in an agent run.

## Executables versus shell syntax

`nix shell -c` executes an executable with separate arguments; it does **not**
interpret shell syntax. Never combine the executable and its arguments into one
quoted string:

```bash
# Wrong: looks for an executable named "jq .name data.json".
nix shell nixpkgs#jq -c "jq .name data.json"
# Right: quote individual arguments as needed.
nix shell nixpkgs#jq -c jq -r '.name' 'data file.json'
```

Your outer shell processes unquoted pipes, redirects, variables, and globs before
Nix runs. A redirect such as `> result.txt` can stay outside; commands that need
the added tools must run inside. Use an explicit shell for pipelines, `cd`, loops,
or expansion that must happen inside the environment:

```bash
nix shell nixpkgs#curl nixpkgs#jq -c bash -euo pipefail -c \
  'curl -fsSL https://example.com/a.json | jq -r .name' > result.txt
```

`pipefail` propagates a failing pipeline stage instead of hiding it behind a
successful final command. Pass dynamic values as arguments or environment
variables rather than interpolating them into shell code.

## Python imports

Do **not** just add `nixpkgs#python3Packages.<name>` alongside `python3`: that does
not compose an interpreter that can import it. Use `python3.withPackages`:

```bash
nix shell "$(
  nix eval nixpkgs#python3 --raw --apply \
    'py: (py.withPackages (p: [ p.requests p.pyyaml ])).drvPath'
)^out" -c python3 job.py
```

Replace the package list as needed; import names may differ from Nix attributes
(`yaml` → `pyyaml`, `bs4` → `beautifulsoup4`). Use `.drvPath` with `^out` **outside**
the substitution so Nix realizes the output; an evaluated `.outPath` alone may
not exist yet. This recipe needs neither `<nixpkgs>` nor `--impure`.

Add other tools to the same `nix shell` invocation when needed, for example
`nixpkgs#jq` before `-c bash -euo pipefail -c 'python3 job.py | jq .'`.
For direct store-path execution, realize it first with
`nix build --no-link --print-out-paths`.

## Package names and default apps

Package attributes and executable names need not match:

```bash
nix shell nixpkgs#ripgrep -c rg 'pattern' .
nix run nixpkgs#jq -- -r '.name' data.json
```

`nix run` selects a flake app or the package's default executable; matching the
package attribute's name is not required. Use `nix shell -c` when you need a
specific executable or several packages. If an attribute is unknown, look it up
with `nix search nixpkgs <query>`.
