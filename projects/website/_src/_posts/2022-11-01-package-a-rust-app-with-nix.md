---
title: How to package a Rust app using Nix
description: Here's a quick tutorial on how to nixify your cargo-based rust project
tags: [ nix, rust ]
---

Sometimes I see people looking around for a cookbook to package  rust project.
Here's a simple way to do it. As a plus, I'll also show how to export the package
through a flake.

I'll use nixpkgs' `buildRustPackage`. There's a few [other
tools](https://nixos.wiki/wiki/Rust#Packaging_Rust_projects_with_nix), my
favorite being [crate2nix](https://github.com/kolloch/crate2nix), but we'll
leave that to a future tutorial.

> Note: In this tutorial, we'll be nixifying a crate on its own repo. If you
> want to package it elsewhere, remember to use `fetchFromGitHub` (and friends)
> with `src` instead of `lib.cleanSource ./.`;

## Ready, set, go!

Let's start by scaffolding a rust project with `cargo`:
```bash
nix run nixpkgs#cargo init foo-bar
cd foo-bar
```

Let's also generate a `Cargo.lock`:
```bash
nix run nixpkgs#cargo update
```

And stage the files so that Nix sees them:
```bash
git add .
```

Okay, start by creating a `default.nix` file and add this minimal example:
```nix
{ pkgs ? import <nixpkgs> { } }:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "foo-bar";
  version = "0.1";

  cargoLock.lockFile = ./Cargo.lock;

  src = pkgs.lib.cleanSource ./.;
}
```

Now let's build it:
```bash
# Nix3 command
nix build -f default.nix
# The nix legacy command also works
nix-build default.nix
```

I swear. That's really what you need for a working package. Nix's happy path is
really happy.

```bash
./result/bin/foo-bar
# Hello, world!
```

## Flakefy it!

Let's add a `flake.nix` now. Here's a minimal example:
```nix
{
  description = "Foo Bar";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = nixpkgs.legacyPackages;
    in {
      packages = forAllSystems (system: {
        default = pkgsFor.${system}.callPackage ./. { };
      });
    };
}
```

Add any systems you want to support to `supportedSystems` list, of course.

The build is now more reproducible, as it will use the `nixpkgs` commit locked
into `flake.lock`:

```bash
nix build
```

You even get a dev shell for free:

```bash
nix develop
```

## Augment our dev shell

Let's say you want additional tooling, such as a LSP, a formatter, a linter...
You can augment this shell with additional packages!

Create a `shell.nix` file:
```nix
{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  # Get dependencies from the main package
  inputsFrom = [ (pkgs.callPackage ./default.nix { }) ];
  # Additional tooling
  buildInputs = with pkgs; [
    rust-analyzer # LSP Server
    rustfmt       # Formatter
    clippy        # Linter
  ];
}
```

This will also allow the older `nix-shell` to work.

Nice. Let's try it:
```bash
# Nix3 command
nix develop -f shell.nix
# Nix legacy command
nix-shell shell.nix
```

> Note: If you use a shell other than bash and want to use `nix develop` with
> it, append a `-c $SHELL` to the command.

Awesome, we have augmented our shell with additional rust tooling :)

Let's add it to our flake:

```nix
{
  description = "Foo Bar";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = nixpkgs.legacyPackages;
    in {
      packages = forAllSystems (system: {
        default = pkgsFor.${system}.callPackage ./default.nix { };
      });
      devShells = forAllSystems (system: {
        default = pkgsFor.${system}.callPackage ./shell.nix { };
      })
    };
}
```

I've replaced `./.` with `./default.nix` to make it more explicit.

Calling it is easier and more reproducible now:
```bash
nix develop
```

## Grab metadata automagically

Setting the metadata (name, version) on two separate places (`Cargo.toml` and
`default.nix`) is boring, we can do better! Let's try out `importTOML` in our
`default.nix`:

```nix
{ pkgs ? import <nixpkgs> { } }:
let manifest = (pkgs.lib.importTOML ./Cargo.toml).package;
in
pkgs.rustPlatform.buildRustPackage rec {
  pname = manifest.name;
  version = manifest.version;

  cargoLock.lockFile = ./Cargo.lock;

  src = pkgs.lib.cleanSource ./.;
}
```

Nice.

## Closing thoughts

AFAIK, this is the simplest way to package Rust crates. This should also make
the project acessible for both flake/nix3 users and for those who still use
`nix-build` and `nix-shell`.

I decided to keep this focused on `buildRustPackage` that, while simple and
vanilla, has a few drawbacks (such as rebuilds starting from scratch). If
you're interested in incremental building, keep tuned: I will probably make a
post about `crate2nix` soon(tm).

> Spotted an error? See something I should improve or reword? Let me know at
> [hi@m7.rs](mailto:hi@m7.rs)!
