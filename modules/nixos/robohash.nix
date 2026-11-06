{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.robohash;
in {
  options.services.robohash = {
    enable = lib.mkEnableOption "the Robohash avatar generator";
    package = lib.mkPackageOption pkgs "robohash" {};
    port = lib.mkOption {
      type = lib.types.port;
      default = 9010;
      description = "Port on which Robohash listens on 127.0.0.1.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.robohash = {
      description = "Robohash avatar generator";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --port=${toString cfg.port}";
        DynamicUser = true;
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        MemoryMax = "256M";
        TasksMax = 16;
        UMask = "0077";
      };
    };
  };
}
