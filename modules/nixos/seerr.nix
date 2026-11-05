{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.seerr;
  declarative = cfg.declarative;
  format = pkgs.formats.json {};
  configuration = format.generate "seerr.json" {
    version = 1;
    inherit (declarative) owner settings;
  };
in {
  options.services.seerr.declarative = {
    enable = lib.mkEnableOption "authoritative Seerr configuration (requires the declarative OIDC fork)";
    owner = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs ["provider" "subject" "email" "username"] (name:
          lib.mkOption {
            type = lib.types.nonEmptyStr;
            description = "Owner's ${name}; subject is the exact OIDC sub, not an email or username.";
          });
      };
      default = {};
      description = "Explicitly provisioned owner identity, pinned to Seerr user 1.";
    };
    settings = lib.mkOption {
      type = format.type;
      default = {};
      description = "Authoritative settings. Use file references for credentials, never secret values.";
    };
    credentials = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "Secret files loaded into /run/credentials/seerr.service under the given names.";
    };
  };

  config = lib.mkIf (cfg.enable && declarative.enable) {
    systemd.services.seerr = {
      environment.SEERR_CONFIG_FILE = configuration;
      restartTriggers = [configuration];
      serviceConfig.LoadCredential = lib.mapAttrsToList (name: file: "${name}:${file}") declarative.credentials;
    };
  };
}
