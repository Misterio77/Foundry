#!/usr/bin/env bash

openring -S <( yq -r '.[].feed' blogs.yml ) \
    < webring-in.yml \
    > webring.yml
