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
    Restart = "on-failure";
    StartLimitBurst = 2;
    ExecStopPost = pkgs.writeShellScript "stop-post" ''
      # When it requires a discovery
      if [ "$SERVICE_RESULT" == "exit-code" ]; then
        ${lib.getExe config.services.vdirsyncer.package} discover --no-list
      fi
    '';
  };
}
