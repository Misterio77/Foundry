{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  upstream = name: (import (inputs.home-manager + "/modules/services/${name}.nix") {inherit config lib pkgs;}).options.services.${name};
  execCondition = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Optional systemd ExecCondition checked before syncing each account or pair.";
  };
  service = cfg:
    {Type = "oneshot";}
    // lib.optionalAttrs (cfg.execCondition != null) {ExecCondition = cfg.execCondition;};
  syncUnits = {
    name,
    frequency,
    commands,
    service,
  }: {
    services = lib.mapAttrs' (target: command:
      lib.nameValuePair "${name}-${target}" {
        Unit.Description = "${name} synchronization for ${target}";
        Service = service // {ExecStart = command;};
      })
    commands;
    timers = lib.mapAttrs' (target: _:
      lib.nameValuePair "${name}-${target}" {
        Unit.Description = "${name} synchronization for ${target}";
        Timer = {
          OnCalendar = frequency;
          Unit = "${name}-${target}.service";
        };
        Install.WantedBy = ["timers.target"];
      })
    commands;
  };
  mail = config.services.mbsync;
  dav = config.services.vdirsyncer;
  mailAccounts = lib.filterAttrs (_: account: account.mbsync.enable) config.accounts.email.accounts;
  davEnabled = lib.filterAttrs (_: account: account.vdirsyncer.enable);
  pairs =
    lib.mapAttrs' (name: _: lib.nameValuePair "calendar_${name}" {}) (davEnabled config.accounts.calendar.accounts)
    // lib.mapAttrs' (name: _: lib.nameValuePair "contacts_${name}" {}) (davEnabled config.accounts.contact.accounts);
  mailOptions = lib.optional mail.verbose "--verbose" ++ lib.optional (mail.configFile != null) "--config ${mail.configFile}";
  davOptions = lib.optional (dav.verbosity != null) "--verbosity ${dav.verbosity}" ++ lib.optional (dav.configFile != null) "--config ${dav.configFile}";
  davCommand = "${dav.package}/bin/vdirsyncer ${lib.concatStringsSep " " davOptions}";
in {
  disabledModules = [
    (inputs.home-manager + "/modules/services/mbsync.nix")
    (inputs.home-manager + "/modules/services/vdirsyncer.nix")
  ];

  # Retain upstream scheduling and command options, replacing only unit generation.
  options.services = {
    mbsync = upstream "mbsync" // {inherit execCondition;};
    vdirsyncer = upstream "vdirsyncer" // {inherit execCondition;};
  };

  config = lib.mkMerge [
    (lib.mkIf mail.enable {
      assertions = [
        (lib.hm.assertions.assertPlatform "services.mbsync" pkgs lib.platforms.linux)
      ];
      services.mbsync.package = lib.mkDefault config.programs.mbsync.package;
      systemd.user = syncUnits {
        name = "mbsync";
        inherit (mail) frequency;
        commands = lib.mapAttrs (name: account: let
          targets =
            if account.mbsync.groups == {}
            then [name]
            else lib.attrNames account.mbsync.groups;
        in "${mail.package}/bin/mbsync ${lib.concatStringsSep " " (mailOptions ++ targets)}")
        mailAccounts;
        service =
          service mail
          // lib.optionalAttrs (mail.preExec != null) {ExecStartPre = mail.preExec;}
          // lib.optionalAttrs (mail.postExec != null) {ExecStartPost = mail.postExec;};
      };
    })
    (lib.mkIf dav.enable {
      services.vdirsyncer.package = lib.mkDefault config.programs.vdirsyncer.package;
      systemd.user = syncUnits {
        name = "vdirsyncer";
        inherit (dav) frequency;
        commands =
          lib.mapAttrs (name: _: [
            "${davCommand} metasync ${name}"
            "${davCommand} sync ${name}"
          ])
          pairs;
        service = service dav;
      };
    })
  ];
}
