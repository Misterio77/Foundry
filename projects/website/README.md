# misterio.me

## About
[![builds.sr.ht status](https://builds.sr.ht/~misterio/misterio.me.svg)](https://builds.sr.ht/~misterio/misterio.me?)
[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://builtwithnix.org)

My personal website.

Water.css + Jekyll

See [my blog post](https://misterio.me/2021/06/08/hello-world.html) for more information.

## Developing

First install ruby and bundler, then run `bundle install`.

Now you can use `bundle exec jekyll build` to build, and `bundle exec jekyll serve` to serve locally.

### Nix

If you're using Nix, just run `nix develop` to get a shell with everything you need.

You can also use `nix build` to build the site, ready for deployment. You can serve it locally using `nix run`.
