{
  inputs,
  lib,
  ...
}: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
in {
  # system-manager's nix module has no nix.registry option (unlike NixOS), so
  # generate the system flake registry directly, mirroring nixpkgs' generator.
  # Registers every flake input, including `self` — the hydra auto-upgrade
  # resolves `nix flake metadata self` through this.
  environment.etc."nix/registry.json".text = builtins.toJSON {
    version = 2;
    flakes =
      lib.mapAttrsToList (name: flake: {
        exact = true;
        from = {
          id = name;
          type = "indirect";
        };
        to =
          {
            type = "path";
            path = flake.outPath;
          }
          // lib.filterAttrs (n: _: n == "lastModified" || n == "rev" || n == "narHash") flake;
      })
      flakeInputs;
  };

  nix = {
    enable = true;
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
      ];
      extra-substituters = ["https://cache.m7.rs"];
      extra-trusted-public-keys = ["cache.m7.rs:kszZ/NSwE/TjhOcPPQ16IuUiuRSisdiIwhKZCxguaWg="];
      trusted-users = ["@sudo"];
      warn-dirty = false;
    };
  };
}
