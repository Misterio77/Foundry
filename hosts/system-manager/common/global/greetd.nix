{
  config,
  lib,
  pkgs,
  ...
}: let
  sessionPackages = lib.flatten (lib.mapAttrsToList (_: user: user.home.exportedSessionPackages) config.home-manager.users);
  sessionDirectories = lib.makeSearchPath "share/wayland-sessions" sessionPackages;
  # greetd links nix's linux-pam, which only understands `include`/`substack`
  # (not Ubuntu's Debian `@include`) and can only load nix's own modules by
  # absolute path. So we can't chain into Ubuntu's /etc/pam.d/login stack; use
  # a self-contained one built from nix modules.
  pamSecurity = "${pkgs.linux-pam}/lib/security";
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

  # nixpkgs' pam_unix execs its verification helper from the fixed path
  # /run/wrappers/bin/unix_chkpwd, so pam_unix auth silently fails until that
  # setuid wrapper exists. Provide it (as NixOS does) so pam_unix works for
  # both root callers (greetd) and unprivileged ones (hyprlock).
  security.wrappers.unix_chkpwd = {
    setuid = true;
    owner = "root";
    group = "root";
    source = "${pkgs.linux-pam}/bin/unix_chkpwd";
  };

  environment.etc = {
    # These paths are ours (Ubuntu ships no greetd/hyprlock), but a prior
    # System Manager activation can leave them on disk without recording them
    # in its etc state, so a re-activation sees them as unmanaged and aborts.
    # replaceExisting backs the stale file up and relinks instead of erroring.
    "pam.d/greetd" = {
      replaceExisting = true;
      # greetd authenticates as root, so pam_unix reads /etc/shadow directly
      # (no setuid unix_chkpwd needed). pam_systemd registers the logind
      # session the Wayland session relies on (XDG_RUNTIME_DIR, seat).
      text = ''
        auth      [success=1 default=ignore] ${pamSecurity}/pam_unix.so nullok
        auth      requisite                  ${pamSecurity}/pam_deny.so
        auth      required                   ${pamSecurity}/pam_permit.so

        account   [success=1 default=ignore] ${pamSecurity}/pam_unix.so
        account   requisite                  ${pamSecurity}/pam_deny.so
        account   required                   ${pamSecurity}/pam_permit.so

        password  required                   ${pamSecurity}/pam_deny.so

        session   required                   ${pamSecurity}/pam_loginuid.so
        session   required                   ${pamSecurity}/pam_unix.so
        session   optional                   ${pamSecurity}/pam_env.so
        session   optional                   ${pkgs.systemd}/lib/security/pam_systemd.so
      '';
    };
    "pam.d/hyprlock" = {
      replaceExisting = true;
      text = ''
        auth include login
      '';
    };
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
