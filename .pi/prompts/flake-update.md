---
description: Audit an uncommitted flake update
---
Audit the flake update in `@`; follow AGENTS.md.

1. Run `nix flake check --no-build --show-trace` first. Fix straightforward compatibility failures as they appear; ask before policy or behavior changes.
2. Compare `flake.lock` with `@-` and identify changed direct root inputs. For each except nixpkgs, fetch the upstream compare/changelog and check changed modules/options against their actual use in this repo.
3. Treat nixpkgs lightly: evaluate old and new direct NixOS/Home Manager package lists, compare package names/versions, and inspect only noteworthy service upgrades, removals, or breaking releases. Avoid a recursive closure diff.
4. Re-run evaluation, format touched Nix files, and build only focused compatibility fixes when useful—skip heavyweight builds unless requested.
5. Report actionable risks, fixes made, remaining warnings, and verification. Update the current jj description with revision ranges and meaningful upstream changes, but don't finalize or push it.
