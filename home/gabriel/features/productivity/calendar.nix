{config, pkgs, lib, ...}: {
  home.persistence = {
    "/persist".directories = [
      "Calendars"
      "Contacts"
      ".local/share/vdirsyncer"
    ];
  };

  accounts.calendar.basePath = "Calendars";

  programs.vdirsyncer.enable = true;
  services.vdirsyncer.enable = true;
  # Only run if gpg is unlocked
  systemd.user.services.vdirsyncer.Service = {
    ExecCondition = let
      gpgCmds = import ../cli/gpg-commands.nix {inherit pkgs config lib;};
    in ''
      /bin/sh -c "${gpgCmds.isUnlocked}"
    '';
  };
}
