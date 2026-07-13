#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq httpie

image="$(echo "$1" | rev | cut -d '/' -f1 | rev | cut -d '.' -f1)"
clientid="0c2b2b57cdbe5d8"

image=$(https api.imgur.com/3/image/$image Authorization:"Client-ID $clientid" | jq -r '.data | "\(.description)|\(.type)|\(.id)"')

jq -n \
    --arg name "$(echo $image | cut -d '|' -f 1)" \
    --arg ext "$(echo $image | cut -d '|' -f 2 | cut -d '/' -f 2)" \
    --arg id "$(echo $image | cut -d '|' -f 3)" \
    --arg sha256 "$(nix-prefetch-url https://i.imgur.com/$id.$ext)" \
    '{"name": $name, "ext": $ext, "id": $id, "sha256": $sha256}'
