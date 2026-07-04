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
    sessionVariables = {
      NH_FLAKE = "$HOME/Foundry";
    };
    persistence = {
      "/persist".directories = [
        # Private authored work: notes, papers, drafts, research, and experiments.
        "Atelier"
        # Public/deployable Nix infrastructure, services, packages, and site.
        "Foundry"

        # Ad hoc backups: game saves, database dumps, and other pre-stupidity snapshots.
        "Backups"
        # Static official documents: PDFs, scans, contracts, certificates.
        "Documents"
        # Quarantine for unsorted browser/chat/download detritus.
        "Downloads"
        # External checkouts, upstream contributions, and temporary cloned repos.
        "Projects"
      ];
    };
  };
}
