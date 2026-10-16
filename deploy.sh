#!/usr/bin/env bash
# Helper script to quickly deploy config to a host. Use it for rapid iteration.
set -euo pipefail

# rssh authenticates remote sudo through the forwarded SSH agent.
export NIX_SSHOPTS="${NIX_SSHOPTS:+$NIX_SSHOPTS }-A"

hosts="${1:-}"
if [ -z "$hosts" ]; then
  echo "No hosts to deploy" >&2
  exit 2
fi
shift

for host in ${hosts//,/ }; do
  system=$(nixos-rebuild build --flake ".#$host" --no-link "$@")

  # Elevating activation alone does not allow importing unsigned local builds.
  nix copy --no-check-sigs --substitute-on-destination \
    --to "ssh://$host?remote-program=sudo%20nix-store" "$system"

  # With a prebuilt path there is no flake to evaluate for nixos-rebuild's re-exec.
  nixos-rebuild test --no-reexec --store-path "$system" --target-host "$host" --sudo "$@"
done
