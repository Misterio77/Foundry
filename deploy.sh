#!/usr/bin/env bash
# Helper script to quickly deploy config to a host. Use it for rapid iteration.
export NIX_SSHOPTS="-A"

hosts="$1"
shift

if [ -z "$hosts" ]; then
    echo "No hosts to deploy"
    exit 2
fi

for host in ${hosts//,/ }; do
   nixos-rebuild --flake .\#$host test --target-host $host --use-substitutes $@
done
