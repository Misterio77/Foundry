{
  inputs,
  lib,
  ...
}: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
in {
  nix = {
    settings = {
      extra-substituters = lib.mkAfter ["https://cache.m7.rs"];
      extra-trusted-public-keys = ["cache.m7.rs:kszZ/NSwE/TjhOcPPQ16IuUiuRSisdiIwhKZCxguaWg="];
      # Nix daemon trust is root-equivalent; wheel users must authenticate via sudo.
      # Builder service accounts add their trust separately in the relevant modules.
      trusted-users = ["root"];
      auto-optimise-store = lib.mkDefault true;
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
        # Hydra and auto-upgraders fetch flake URLs with pinned commit-signing keys.
        "verified-fetches"
      ];
      warn-dirty = false;
      system-features = [
        "kvm"
        "big-parallel"
        "nixos-test"
      ];
      flake-registry = ""; # Disable global flake registry
    };
    gc = {
      automatic = true;
      dates = "daily";
      # Keep generations from the past week
      options = "--delete-older-than 7d";
    };

    # Add each flake input as a registry and nix_path
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };
}
