[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://builtwithnix.org)
[![hydra status](https://img.shields.io/endpoint?url=https://hydra.m7.rs/job/foundry/main/hosts.atlas/shield)](https://hydra.m7.rs/jobset/foundry/main#tabs-jobs)

# Foundry

My public infrastructure monorepo: the NixOS/home-manager configuration that
runs all my machines, plus the source of the personal projects it deploys.
Requires [Nix flakes](https://nixos.wiki/wiki/Flakes).

Looking for something simpler to start out with flakes? Try [my starter config repo](https://github.com/Misterio77/nix-starter-config).

## Repository layout

```text
hosts/          per-machine NixOS configurations (atlas, alcyone, ...)
home/           home-manager configuration (feature-flagged)
modules/        reusable nixos/ and home-manager/ modules
overlays/, pkgs/ package overlays and custom packages
lib/            pure-Nix Material You color engine
wallpapers/     wallpaper collection
projects/       my public projects deployed from here (e.g. the m7.rs website)
```

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
- **Declarative theming**: wallpapers and a pure-Nix **Material You** color engine
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

## AI usage note

Since June 2026, I've been trying out LLM assistance in my workflows. So far it feels pretty good; brainstorming helps me a lot with decision paralysis. I'm trying to keep my use bounded and disclosed. I think it's a useful tool, but it should be adopted with care.

I will write a decent blog post about my opinions on AI at some point. The gist is:

- These things are useful for bounded tasks with good docs and reviews, but suck at owning architecture or accountability
- There's no going back now that open-weight models run on consumer hardware, we can't uninvent them
- Boycotting AI does not help by itself; non-use is not a political strategy
- We need clear LLM policy on projects rather than trying (and failing) to forbid it
- Disclosure is very important, and trying to pass LLM output off as human-written is disrespectful
- LLMs should never have been built by scraping and exploiting our art and work
- If copyright doesn't protect our creations, it shouldn't protect their models; support open-weight models and distillation as harm reduction
- We need regulation, decentralization, and redistribution of the value LLMs generate
- Machines can't be horny, thus can't create art; LLMs are for utility, not art or craft. Pay an artist instead

Some bibliography I'd recommend:
- Alice's ["AI Sucks. Hating it is not enough."](https://shaping.systems/blog/ai-sucks-hating-it-is-not-enough/) (please read it, it's an amazing piece)
- Drew's ["The cults of TDD and GenAI"](https://drewdevault.com/blog/Cult-of-TDD-and-LLMs/) (I don't really agree with the non-use perspective, but otherwise I think it's solid)
- Armin's ["Communities of Not"](https://lucumr.pocoo.org/2026/6/6/communities-of-not/) and ["The Center Has a Bias"](https://lucumr.pocoo.org/2026/4/11/the-center-has-a-bias/) (I'm not a centrist politically, though)
