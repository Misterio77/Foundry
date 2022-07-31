#!/usr/bin/env -S nix shell nixpkgs#openring nixpkgs#yq --command bash

openring -S <( yq -r '.[].feed' blogs.yml ) \
    -n 5 \
    < webring-in.yml \
    > webring.yml
