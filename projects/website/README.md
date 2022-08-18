# fontes.dev.br

## About
[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://nixos.org)

My personal website and gemini capsule.

Licensed under MIT (code) and CC BY-SA 4.0 (content), available at both
[sourcehut](https://git.sr.ht/~misterio/website) and
[github](https://github.com/misterio77/:ebsite)

Currently deployed at [sourcehut pages](https://srht.site).

## Developing

First install ruby and bundler, then run `bundle install`.

Now you can use `bundle exec jekyll build` to build, and `bundle exec jekyll
serve` to serve locally.

### Nix

If you're using Nix, just run `nix develop` to get a shell with everything you
need.

You can also use `nix build` to build the site, ready for deployment. You can
serve it locally using `nix run`.
