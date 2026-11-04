{
  config,
  pkgs,
  lib,
  ...
}: let
  gpgCmds = import ../cli/gpg-commands.nix {inherit pkgs config lib;};
in {
  home.persistence = {
    "/persist".directories = [
      "Calendars"
      "Contacts"
      ".local/share/vdirsyncer"
    ];
  };

  accounts.calendar.basePath = "Calendars";

  programs.vdirsyncer.enable = true;
  services.vdirsyncer = {
    enable = true;
    execCondition = ''/bin/sh -c "${gpgCmds.isUnlocked}"'';
  };
}
