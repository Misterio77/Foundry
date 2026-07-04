[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://builtwithnix.org)
[![hydra status](https://img.shields.io/endpoint?url=https://hydra.m7.rs/job/foundry/main/hosts.atlas/shield)](https://hydra.m7.rs/jobset/foundry/main#tabs-jobs)

# Foundry

My public infrastructure monorepo: the NixOS/home-manager configuration that
runs all my machines, plus the source of the personal projects it deploys.
Requires [Nix flakes](https://nixos.wiki/wiki/Flakes).

Looking for something simpler to start out with flakes? Try [my starter config repo](https://github.com/Misterio77/nix-starter-config).

## Repository layout

```text
flake.nix, flake.lock   the monorepo flake (hosts, modules, packages, CI)
hosts/                  per-machine NixOS configurations (atlas, alcyone, ...)
home/                   home-manager configuration (feature-flagged)
modules/                reusable nixos/ and home-manager/ modules
overlays/, pkgs/        package overlays and custom packages
hydra.nix, .hydra.json  Hydra CI/CD jobset (builds every host, binary cache)
deploy.sh               deployment helper
projects/               my public projects that this config deploys
  website/              github.com/misterio77/website (served at m7.rs)
  themes/               github.com/misterio77/themes (themes & wallpapers)
```

The `projects/` subtrees were vendored in from their own repos **with full git
history** (via `git filter-repo --to-subdirectory-filter` + an unrelated-history
merge), so this monorepo now owns the sources of the things it deploys. They are
still mirrored to their standalone GitHub repos. See `AGENTS.md` for the
input-wiring status.

**Highlights**:

- **NixOS configurations**: desktop, laptop, servers
- **Opt-in persistence** through impermanence + blank snapshotting
- **Encrypted** single **BTRFS** partition (with **disko** for declarative partitioning)
- **Secure Boot** via **lanzaboote**
- Fully **declarative** **self-hosted** stuff
- Deployment **secrets** using **sops-nix**
- **Mesh networked** hosts with **tailscale** and **headscale**
- Flexible **Home Manager** configs through **feature flags**
- Extensively configured **hyprland** environment
- **Declarative theming**: wallpapers + a from-scratch pure-Nix **Material You** color engine (no matugen/IFD)
- **Hydra CI/CD** builds every host, serves a binary cache, and hosts auto-upgrade by pull deployment


## About the installation

All my computers use a single btrfs (encrypted on all except headless systems)
partition, with subvolumes for `/nix`, a `/persist` directory (which I opt in
using `impermanence`), swap file, and a root subvolume (cleared on every boot).

Home-manager is used as a NixOS module, integrated via `home-manager.users`.


## Secrets

For deployment secrets (such as user passwords and server service secrets), I'm
using the awesome [`sops-nix`](https://github.com/Mic92/sops-nix). All secrets
are encrypted with my personal PGP key (stored on a YubiKey), as well as the
relevant systems' SSH host keys.

On my desktop and laptop, I use `pass` for managing passwords, which are
encrypted using (you bet) my PGP key. This same key is also used for mail
signing, as well as for SSH'ing around.

## Tooling and applications I use

Most relevant user apps daily drivers:

- hyprland + hypridle + hyprlock
- waybar
- helix
- fish
- alacritty
- qutebrowser
- neomutt + mbsync
- khal + khard + todoman + vdirsyncer
- gpg + pass
- tailscale
- podman
- zathura
- wofi
- bat + fd + rg
- kdeconnect

Some of the services I host:

- hydra
- jellyfin
- *arrs (including torrent and usenet)
- prometheus
- websites (such as https://m7.rs)
- minecraft
- headscale

Nixy stuff:

- sops-nix
- impermanence
- disko
- lanzaboote
- home-manager
- and NixOS and nix itself, of course :)

Let me know if you have any questions about them :)

## Unixpornish stuff
![fakebusy](https://i.imgur.com/PZ4L7TR.png)
![clean](https://i.imgur.com/T5FjqbZ.jpg)
