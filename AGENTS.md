# Foundry Conventions for LLMs

## Repository

Foundry is my public infra monorepo (colocated jj/git — use `jj`, not `git`).
It is the NixOS/home-manager config, plus:

- `projects/website/` — the site served at m7.rs, vendored from
  `github:misterio77/website` with full history and wired as a local flake input
  (`path:./projects/website`), so the monorepo builds it from its own tree; still
  mirrored to the standalone repo.
- `wallpapers/` — my wallpaper collection. Each entry in `list.json` carries a
  committed `sourceColor` (matugen's extracted seed), and they're exposed as
  `pkgs.wallpapers` plus a Hydra-cached `wallpapers` package (imgur is upstream).
- `lib/` — a from-scratch pure-Nix implementation of Material You color science
  (`math`, `hct`, `palettes`, `scheme`, `material-you`), validated bit-for-bit
  against matugen. `modules/home-manager/colors.nix` uses it via
  `outputs.lib.material-you.generateColorscheme` to produce colorschemes during
  evaluation — no matugen, no import-from-derivation. Adding a wallpaper needs a
  one-time `matugen image` run to seed its `sourceColor` in `list.json`.

## Commit Messages

Conventional commits: `type(scope): description`

- `type`: `feat`, `fix`, `refactor`, `chore`, `WIP`
- `scope`: path-based, reflecting what part of the config changed. Examples:
  - `home/{feature}` for home-manager features: `home/calendar`, `home/opencode`, `home/helix`
  - `{host}` or `{host}/{service}` for host-specific: `pleione`, `alcyone/firefly`, `merope/recyclarr`
  - Just the component for shared/global: `grafana`, `minecraft`, `recyclarr`
  - `projects/{name}` for vendored project sources: `projects/website`
  - `lib` / `wallpapers` for the color engine and wallpaper collection
- Message is lowercase, no period at end.

### Flake Lock Bumps

When describing a `flake.lock` bump (e.g. after `nix flake update <input>`), summarize
what actually changed in the bumped input(s), not just the revision hashes:

1. Get the old → new revisions from the `nix flake update` output or `flake.lock` diff.
2. Fetch the upstream changelog between them (`gh`/GitHub compare API, or a local clone
   in `/tmp`): `curl -s https://api.github.com/repos/<owner>/<repo>/compare/<old>...<new>`.
3. In the commit body, note the short hash range and a brief bullet list of the
   meaningful changes (commits/files), so the diff is reviewable without leaving the repo.

Example:

```
chore(flake): update website input

Update website from f6c09b0b to 70386bb7 (2 commits, docs-only):
- add _src/llms.txt
- remove stale _src/portfolio.md and its references in llms.txt
```

## Directory Structure

```
.
├── home/gabriel/          # Home Manager user config
│   ├── features/          #   Feature modules (cli/, desktop/, productivity/, helix/, etc.)
│   │   └── {feature}/
│   │       ├── default.nix  # Feature flag + imports
│   │       └── *.nix        # Specific tool configs
│   ├── global/            #   Always-imported config (xdg, etc.)
│   ├── {hostname}.nix     #   Per-host home-manager config
│   └── generic.nix        #   Non-impermanence fallback
├── hosts/                 # NixOS host configs
│   ├── common/            #   Shared across hosts
│   │   ├── global/        #     Always-imported
│   │   ├── optional/      #     Opt-in modules
│   │   └── secrets.yaml   #     SOPS-encrypted shared secrets
│   └── {hostname}/        #   Per-host (atlas, maia, alcyone, celaeno, merope, pleione, taygeta)
│       ├── default.nix    #     NixOS module
│       ├── hardware-configuration.nix
│       └── secrets.yaml   #     Host-specific secrets (optional)
├── modules/               # Custom NixOS & HM modules
│   ├── nixos/
│   └── home-manager/
├── overlays/              # Package overlays and patches (incl. pkgs.wallpapers)
│   └── default.nix
├── pkgs/                  # Custom packages
│   └── default.nix
├── lib/                   # Pure-Nix Material You color engine
│   ├── math.nix           #   hand-rolled float transcendentals
│   ├── hct.nix            #   sRGB<->CAM16<->HCT + solver
│   ├── palettes.nix       #   tonal palettes
│   ├── scheme.nix         #   DynamicColor MD3 roles
│   └── material-you.nix   #   generateColorscheme (used by colors.nix)
├── wallpapers/            # Wallpaper collection + committed source colors
├── projects/              # Vendored public projects
│   └── website/           #   github.com/misterio77/website (served at m7.rs)
├── flake.nix              # Flake entry point
├── deploy.sh              # nixos-rebuild wrapper
└── .sops.yaml             # SOPS encryption keys
```

## Code Style

- **Formatter**: Alejandra (`nix fmt <file>`). ALWAYS format after edits. Never format unmodified files.
- **Indentation**: 2 spaces, no tabs.
- **Line endings**: LF, final newline, trimmed trailing whitespace.
- **Nix conventions**:
  - Top-level modules are functions taking `{pkgs, lib, config, inputs, ...}`.
  - Use `lib` from `nixpkgs.lib // home-manager.lib` (merged, already in `outputs.lib`).
  - Feature-flag modules use a `default.nix` with a boolean `enable` option gating imports.
  - Prefer `lib.mkOption` / `lib.mkEnableOption` for new options.

## Secrets

- Managed with **sops-nix**, keys defined in `.sops.yaml`.
- Two types of secret files:
  - `hosts/common/secrets.yaml` -- shared across hosts, encrypted to all host age keys.
  - `hosts/{hostname}/secrets.yaml` -- per-host, encrypted to that host only.
- Both are also encrypted to the PGP key `7088C7421873E0DB97FF17C2245CAB70B4C225E9`. It lives on misterio's yubikey.
- **Never** read secrets into context. Ask the user to do it.

## Building and Deploying

- Format check: `nix fmt`
- Build a host (test if it builds): `nixos-rebuild build --flake .#{host}`

- Deploy to this host: use nixos-rebuild: `nixos-rebuild switch --flake .`
- Deploy to another host: use deploy.sh: `./deploy.sh {host}`

- Production, uses CI/CD: Hydra at `hydra.m7.rs` builds all hosts on push; hosts auto-upgrade from the latest successful build (see `modules/nixos/hydra-auto-upgrade.nix`). No need to deploy manually, unless quickly iterating locally.

### Post-deploy verification

After deploying a host, verify the correct revision landed:

1. `ssh {host} -- nix flake metadata self --json | jq .revision -r` — get the deployed commit hash (first 8 chars).
2. `jj log -r 'commit_id("{hash}")'` — map it to a change ID and commit description.
3. Confirm it's the expected commit (should be at or near `main` / the tip of the stack).

## Vdirsyncer Calendar Collections

When adding a remote calendar collection to `home/gabriel/features/productivity/calendar.nix`:

1. First verify the collection exists remotely with `vdirsyncer discover`.
2. Add the collection name (or UUID) string to the `collections` list under the appropriate account.
3. Use a `# Comment` to note the display name if it differs from the ID.

## Nix eval

When verifying config output before deploying:

- NixOS config: `nixosConfigurations.<host>.config.<path>`
- Home-manager (managed by NixOS): `nixosConfigurations.<host>.config.home-manager.users.<user>.<path>`
- Specialised HM variant: `nixosConfigurations.<host>.config.home-manager.users.<user>.specialisation.<variant>.config.<path>`
- `nix build <path>.source --no-link --print-out-paths` to get the built file
- `nix eval <path> --json` to inspect raw attribute values
