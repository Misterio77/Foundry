---
name: nix-shell
description: Use `nix shell` for ephemeral environments and one-off commands without installing packages globally.
---

## nix shell

The canonical form for running a single command in a temporary nix environment:

```
nix shell nixpkgs#<package> -c <command> [args...]
```

The `-c` flag tells `nix shell` to exec the following arguments as a command.
Everything after `-c` is passed straight to the shell, so quoting works naturally.

DO NOT, under any circumstances, double-quote `"<command> [args...]"` together. This will cause bash to treat the entire thing as the executable name:
- Wrong: `nix shell nixpkgs#python3 -c "python3 foo.py arg1 arg2"`
- **RIGHT**: `nix shell nixpkgs#python3 -c python3 foo.py arg1 arg2`

### Single-package one-off

```bash
nix shell nixpkgs#jq -c jq '.foo' file.json
nix shell nixpkgs#yq -c yq eval '.foo.bar' file.yml
nix shell nixpkgs#httpie -c https httpbin.org/json
```

### Multiple packages in one shell

For ephemeral environments with multiple tools (where the "command" is `sh`):

```bash
nix shell nixpkgs#jq nixpkgs#yq nixpkgs#curl -c sh
```

This drops you into an interactive shell with all three available. Exit with `exit` or `^D`.

### When to use `nix run` instead

`nix run` is more concise when you just need to run a tool's default binary and
don't need to control the invoked command name:

```bash
nix run nixpkgs#jq -- -r '.name' file.json
```

Use `nix run` when:
- You want a single command with arguments (everything after `--` is passed to the binary)
- The package's default binary name matches what you need
- You don't need multiple packages simultaneously

Use `nix shell` when:
- You need to chain multiple commands in the same ephemeral environment
- The command name differs from the package name (e.g., `nixpkgs#nodePackages.prettier`)
- You want an interactive shell with multiple tools available

### Python with packages (playwright, requests, etc.)

`nix shell nixpkgs#python3Packages.<name>` doesn't work — the Python binary
won't see the package. Instead, use `nix eval --apply` to get the
`python3.withPackages` derivation path, then ask `nix shell` for its `out` output:

```bash
nix shell "$(
  nix eval nixpkgs#python3 --raw --apply \
    'py: (py.withPackages (p: [ p.requests ])).drvPath'
)^out" -c python3 -c '
import requests
print(requests.get("https://httpbin.org/json").json()["slideshow"]["title"])
'
```

For multiple packages/tools, add them to the same shell:

```bash
nix shell "$(
  nix eval nixpkgs#python3 --raw --apply \
    'py: (py.withPackages (p: [ p.playwright ])).drvPath'
)^out" \
  nixpkgs#chromium \
  -c python3 -c '
from playwright.sync_api import sync_playwright
print("works")
'
```

Important details:

- Use `.drvPath` with `^out`; plain `.outPath` may be unrealized.
- Keep `^out` outside the command substitution, as part of the installable path.
- If invoking the store path directly instead of via `nix shell`, use
  `nix build --no-link --print-out-paths` to realize the output first.

### Finding available packages

```bash
nix search nixpkgs <query>
```

### Replacing missing commands

If a command fails with "command not found", wrap it with nix shell instead of
installing the package globally:

```bash
# instead of: apt install jq  (never)
# instead of: nix profile install nixpkgs#jq  (avoid for one-offs)
nix shell nixpkgs#jq -c jq '.foo' data.json
```
