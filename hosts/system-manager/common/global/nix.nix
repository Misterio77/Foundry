{...}: {
  nix = {
    enable = true;
    settings = {
      auto-optimise-store = true;
      build-users-group = "nixbld";
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
      ];
      extra-substituters = ["https://cache.m7.rs"];
      extra-trusted-public-keys = ["cache.m7.rs:kszZ/NSwE/TjhOcPPQ16IuUiuRSisdiIwhKZCxguaWg="];
      trusted-users = [
        "@sudo"
        "@wheel"
      ];
      warn-dirty = false;
    };
  };
}
