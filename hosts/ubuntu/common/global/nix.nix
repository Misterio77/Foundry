{
  inputs,
  lib,
  ...
}: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
in {
  nix = {
    enable = true;
    # Register every flake input (incl. `self`, which the hydra auto-upgrade
    # resolves via `nix flake metadata self`). Uses the nix.registry option
    # from modules/system-manager/nix-registry.nix.
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
      ];
      extra-substituters = ["https://cache.m7.rs"];
      extra-trusted-public-keys = ["cache.m7.rs:kszZ/NSwE/TjhOcPPQ16IuUiuRSisdiIwhKZCxguaWg="];
      # Nix daemon trust is root-equivalent; sudo users must authenticate to elevate.
      trusted-users = ["root"];
      warn-dirty = false;
    };
  };
}
