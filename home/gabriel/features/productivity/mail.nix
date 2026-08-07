{
  pkgs,
  lib,
  config,
  ...
}: {
  home.persistence = {
    "/persist".directories = ["Mail"];
  };

  accounts.email.maildirBasePath = "Mail";

  programs.msmtp.enable = true;

  programs.mbsync = {
    enable = true;
    package = pkgs.isync.override {
      withCyrusSaslXoauth2 = true;
    };
  };
  services.mbsync = {
    enable = true;
    package = config.programs.mbsync.package;
  };
  # Only run if gpg is unlocked
  systemd.user.services.mbsync.Service.ExecCondition = let
    gpgCmds = import ../cli/gpg-commands.nix {inherit pkgs config lib;};
  in ''
    /bin/sh -c "${gpgCmds.isUnlocked}"
  '';

  # Ensure 'createMaildir' runs after 'linkGeneration'
  home.activation = {
    createMaildir = lib.mkForce (lib.hm.dag.entryAfter ["linkGeneration"] ''
      run mkdir -m700 -p $VERBOSE_ARG ${
        lib.concatStringsSep " " (lib.mapAttrsToList (_: v: v.maildir.absPath) config.accounts.email.accounts)
      }
    '');
  };
}
