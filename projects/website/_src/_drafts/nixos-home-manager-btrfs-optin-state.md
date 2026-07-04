---
title: NixOS + home-manager on BTRFS with opt-in state
description: About my opt-in state NixOS and home-manager setups
tags: nix
---

There's a few blog posts about how opt-in persistence makes NixOS/home-manager
configuration more reliable and dependable, as well as some explaining how they
do it. But this one is mine!

## Stack

For this guide, we'll setup NixOS and home-manager configurations, with the
following characteristics:

### Flakes

I'll be using the `homeConfiguration` output for defining standalone
home-manager, and the usual `nixosConfigurations` output for NixOS hosts.

Of course, our installation will be based on `nixos-unstable`, and we'll set up
Nix with `experimental-features = nix-command flakes`.

### Single BTRFS partition

We'll have subvolumes for nix, persistence, swap(file), and ephemeral root.
Optionally LUKS encrypted.

## Flake setup
