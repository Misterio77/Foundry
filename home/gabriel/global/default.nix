{
  lib,
  config,
  outputs,
  ...
}: {
  imports =
    [
      ./nix.nix
      ./specialisations.nix
      ../features/cli
      ../features/helix
    ]
    ++ (builtins.attrValues outputs.homeManagerModules);

  programs.home-manager.enable = true;

  home = {
    username = lib.mkDefault "gabriel";
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    stateVersion = lib.mkDefault "22.05";
    sessionPath = ["$HOME/.local/bin"];
    sessionVariables = {
      NH_FLAKE = "$HOME/Projects/NixConfig";
    };

    persistence = {
      "/persist".directories = [
        "Backups"
        "Documents"
        "Downloads"
        "Notes"
        "Pictures"
        "Projects"
        "Videos"
        ".local/bin"
      ];
    };
  };
}
