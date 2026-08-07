{
  config,
  lib,
  pkgs,
  ...
}: let
  sessionPackages = lib.flatten (lib.mapAttrsToList (_: user: user.home.exportedSessionPackages) config.home-manager.users);
  sessionDirectories = lib.makeSearchPath "share/wayland-sessions" sessionPackages;
  # Run the selected session in a login shell so /etc/profile (PATH,
  # XDG_DATA_DIRS, ...) is sourced. Kept as a script rather than an inline
  # `bash --login -c 'exec "$@"'`: greetd's command tokenizer rejects the
  # nested POSIX quoting that lib.escapeShellArgs would emit for it.
  sessionWrapper = pkgs.writeScript "greetd-session-wrapper" ''
    #!${lib.getExe pkgs.bashInteractive} --login
    exec "$@"
  '';
  tuigreetCommand = lib.escapeShellArgs [
    (lib.getExe pkgs.tuigreet)
    "--time"
    "--asterisks"
    "--remember"
    "--remember-user-session"
    "--sessions"
    sessionDirectories
    "--session-wrapper"
    "${sessionWrapper}"
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

  systemd = {
    maskedUnits = ["display-manager.service"];
    tmpfiles.rules = ["d /var/cache/tuigreet 0755 greeter greeter - -"];
    services.greetd = {
      wantedBy = ["multi-user.target"];
      # Wants (not Requires) userborn: System Manager restarts the oneshot
      # userborn.service on every activation, and a Requires= would propagate
      # that restart to greetd, tearing down the live session on every switch.
      # After= still orders userborn before greetd at boot.
      wants = [
        "systemd-user-sessions.service"
        "userborn.service"
      ];
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
