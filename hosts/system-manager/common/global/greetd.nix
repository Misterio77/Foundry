{
  config,
  lib,
  pkgs,
  ...
}: let
  sessionPackages = lib.flatten (lib.mapAttrsToList (_: user: user.home.exportedSessionPackages) config.home-manager.users);
  sessionDirectories = lib.makeSearchPath "share/wayland-sessions" sessionPackages;
  tuigreetCommand = lib.escapeShellArgs [
    (lib.getExe pkgs.tuigreet)
    "--time"
    "--asterisks"
    "--remember"
    "--remember-user-session"
    "--sessions"
    sessionDirectories
    "--session-wrapper"
    "${lib.getExe pkgs.bashInteractive} --login -c 'exec \"$@\"' --"
    "--cmd"
    (lib.getExe pkgs.bashInteractive)
  ];
  greetdConfig = (pkgs.formats.toml {}).generate "greetd.toml" {
    terminal.vt = 1;
    default_session = {
      command = tuigreetCommand;
      user = "greeter";
    };
  };
in {
  users = {
    groups.greeter = {};
    users.greeter = {
      isSystemUser = true;
      group = "greeter";
    };
  };

  environment.etc = {
    "pam.d/greetd".text = ''
      auth      include login
      account   include login
      password  include login
      session   include login
    '';
    "pam.d/hyprlock".text = ''
      auth include login
    '';
  };

  systemd = {
    maskedUnits = ["display-manager.service"];
    tmpfiles.rules = ["d /var/cache/tuigreet 0755 greeter greeter - -"];
    services.greetd = {
      wantedBy = ["multi-user.target"];
      wants = ["systemd-user-sessions.service"];
      requires = ["userborn.service"];
      after = [
        "systemd-user-sessions.service"
        "getty@tty1.service"
        "userborn.service"
      ];
      conflicts = ["getty@tty1.service"];
      restartIfChanged = false;
      serviceConfig = {
        Type = "idle";
        ExecStart = "${lib.getExe pkgs.greetd} --config ${greetdConfig}";
        Restart = "always";
        RestartSec = 1;
        IgnoreSIGPIPE = false;
        SendSIGHUP = true;
        TimeoutStopSec = 30;
        KeyringMode = "shared";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "journal";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
      };
    };
  };
}
