---
name: pi-extension-authoring
description: Workflow guidelines for durable Pi package, extension, skill, prompt, and theme changes in Gabs's Nix-managed Pi config. Use before editing ~/.pi/agent or home/gabriel/features/pi.
---

# Pi Authoring for Gabs's Foundry

This is a workflow guardrail, not a duplicate map of the code. Inspect the existing Nix files and follow their current shape.

## First principles

- Read the current Pi docs before relying on API/package behavior: packages, extensions, skills, themes, and TUI docs as relevant.
- Do not edit `~/.pi/agent/*` for durable changes. It is Home Manager output. Temporary experiments are fine, but upstream working changes into Nix before calling them done.
- Prefer Pi packages for third-party/external resources. If a package provides metadata or conventional resource directories, wire it as a package and let Pi discover what it contains.
- Do not split a single external package into separate extension/skill paths unless package discovery genuinely cannot represent it.
- Use `pkgs.buildPiPackage` for package wiring.

## Local vs external

- Gabs-owned code belongs in the local Pi resource areas already wired by the module.
- Third-party code belongs under the external package module pattern already present in the repo.
- When unsure, copy the nearest existing example and adjust minimally. The repo is the source of truth; this skill is just the goblin with a clipboard.

## Change process

1. Inspect current files before editing.
2. For external packages, review the source first. Pi packages can execute code; skills can instruct the agent to do anything.
3. Keep package derivations single-source: if one package contains both extension and skill resources, build/fetch it once.
4. Update package imports/aggregation in the same style as the existing modules.
5. Format touched Nix files only.
6. Evaluate the relevant `programs.pi-coding-agent.settings` values to confirm paths/types are what Pi will receive.
7. If package discovery matters, inspect the built output for `package.json` / conventional resource directories.

## Local extension process

When changing Gabs-owned TypeScript extensions:

1. Keep runtime dependencies in `package.json`; update the lockfile when dependencies change.
2. Run the package's typecheck and formatter/check scripts from the extension package directory.
3. Then format touched Nix files and evaluate the Pi settings/package output.

## Skill content guidelines

Skills in this repo should stay Gabs/repo-specific. Do not paste generic Pi docs into skills; point the agent to read the docs when API details matter.

Good skill material:

- workflow ordering
- local gotchas
- repo-specific verification commands
- decisions that are not obvious from copying nearby Nix

Bad skill material:

- copied API reference
- copied TUI docs
- generic TypeScript/Nix tutorials
- directory maps that duplicate what the Nix files already show

## Reloading

After Home Manager applies config, active Pi sessions may need `/reload` to pick up changed extensions, skills, prompts, or themes.
