---
author: Gabriel Fontes
title: "Use builds.sr.ht with nix flakes"
language: en
tags: nix srht
---

I've recently started migrating from github to sourcehut, and i've been having a blast.

Here's a quick write up on how to use the awesome [builds.sr.ht](https://builds.sr.ht) CI with your shiny [nix flake](https://nixos.wiki/wiki/Flakes)-based project.

## flake.nix
First of all, of course, your project needs a `flake.nix`. More specifically, your flake needs a `outputs.packages.xxx` to be built with `nix build xxx` (as a plus, set your preferred packaged to `outputs.defaultPackage`, so you can build with `nix build`). Here's how this [website](https://sr.ht/~misterio/misterio.me)'s looks like:
```nix
{
  description = "My personal website, blog, and digital garden";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let 
        pkgs = import nixpkgs { inherit system; };
        package = "misterio-me";
      in {
        # Package, specifies what nix builds with 'nix build', in this case builds the website with jekyll
        packages.${package} = pkgs.stdenv.mkDerivation {
          pname = package;
          version = "1.0";
          src = ./.;
          buildPhase = ''
            JEKYLL_ENV=production ${pkgs.jekyll}/bin/jekyll build --destination $out
          '';
          installPhase = "true";
        };
        defaultPackage = self.packages.${system}."${package}";

        # App, specifies what nix does with 'nix run', in this case serves up the website
        apps.${package} = let
          serve = pkgs.writeShellScriptBin "serve" ''
            echo "Serving on: http://127.0.0.1:4000"
            ${pkgs.webfs}/bin/webfsd -f index.html -F -p 4000 -r ${self.packages.${system}.${package}}
          '';
        in {
          type = "app";
          program = "${serve}/bin/serve";
        };
        defaultApp = self.apps.${system}.${package};

        # Development shell, specifies what nix provides with 'nix develop'
        devShell =
          pkgs.mkShell { buildInputs = with pkgs; [ jekyll nodePackages.prettier sass scss-lint ]; };
      });
}
```

I've included it all as a reference, but you can safely ignore `apps` and `devShell`, if you don't need them.

## Build manifest

### Minimal example
Here's what you're probably looking for. This is a minimal `.build.yml` manifest is how you can easily get some sweet nix flakes support on your `builds.sr.ht` runner:
```yml
image: nixos/unstable
packages:
- nixos.nixUnstable
environment:
  NIX_CONFIG: "experimental-features = nix-command flakes"
```
This baby will install `nixUnstable` using `nix-env`, and add the required experimental features to your environment (so you don't have to edit a file or use cli arguments for that).

### How i use it

Just add your `tasks` and `environment` entries as needed. I build and deploy [this website](https://git.sr.ht/~misterio/misterio.me/) to [SourceHut pages](https://srht.site) with [this manifest](https://git.sr.ht/~misterio/misterio.me/tree/main/item/.build.yml):
```yml
image: nixos/unstable
packages:
- nixos.nixUnstable
environment:
  NIX_CONFIG: "experimental-features = nix-command flakes"

oauth: pages.sr.ht/PAGES:RW

tasks:
- build: |
    cd misterio.me
    nix --quiet build
- package: |
    tar -C misterio.me/result -cvz . > site.tar.gz
- upload: |
    acurl -f https://pages.sr.ht/publish/misterio.me -Fcontent=@site.tar.gz
```

Pretty sweet!
