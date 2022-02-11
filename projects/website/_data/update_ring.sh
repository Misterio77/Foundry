#!/usr/bin/env bash

openring -S <( yq -r '.[].feed' blogs.yml ) \
    -n 5 \
    < webring-in.yml \
    > webring.yml
