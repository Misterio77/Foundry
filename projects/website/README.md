# My website

## About
[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://nixos.org)
[![hydra status](https://img.shields.io/endpoint?url=https://hydra.m7.rs/job/foundry/main/pkgs.x86_64-linux.website/shield)](https://hydra.m7.rs/jobset/foundry/main#tabs-jobs)

My personal website.

Licensed under MIT (code) and CC BY-SA 4.0 (content)

## Developing

First install ruby and bundler, then run `bundle install`.

Now you can use `bundle exec jekyll build` to build, and `bundle exec jekyll
serve` to serve locally.

### Nix

Within the Foundry monorepo, run `nix build .#website` to build the site ready
for deployment.
