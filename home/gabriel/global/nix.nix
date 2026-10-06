{
  lib,
  pkgs,
  ...
}: {
  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      # Add user features without overriding the system's enabled features.
      extra-experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"
      ];
      warn-dirty = false;
    };
  };

  home.persistence."/persist".directories = [
    ".local/share/nix" # trusted settings and repl history
  ];
}
