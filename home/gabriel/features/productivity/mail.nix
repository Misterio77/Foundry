{
  pkgs,
  lib,
  config,
  ...
}: let
  gpgCmds = import ../cli/gpg-commands.nix {inherit pkgs config lib;};
in {
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
    execCondition = ''/bin/sh -c "${gpgCmds.isUnlocked}"'';
  };

  # Ensure 'createMaildir' runs after 'linkGeneration'
  home.activation = {
    createMaildir = lib.mkForce (lib.hm.dag.entryAfter ["linkGeneration"] ''
      run mkdir -m700 -p $VERBOSE_ARG ${
        lib.concatStringsSep " " (lib.mapAttrsToList (_: v: v.maildir.absPath) config.accounts.email.accounts)
      }
    '');
  };
}
