{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.seerr;
  declarative = cfg.declarative;
  format = pkgs.formats.json {};
  isFileReference = value:
    lib.isAttrs value
    && builtins.attrNames value == ["file"]
    && (lib.isString value.file || lib.isPath value.file);
  credentialName = file: "secret-${builtins.hashString "sha256" (toString file)}";
  collectFiles = value:
    if isFileReference value
    then [(toString value.file)]
    else if lib.isList value
    then lib.concatMap collectFiles value
    else if lib.isAttrs value
    then lib.concatMap collectFiles (builtins.attrValues value)
    else [];
  secretFiles = lib.unique (collectFiles declarative.settings);
  rewriteFiles = value:
    if isFileReference value
    then {file = "/run/credentials/seerr.service/${credentialName value.file}";}
    else if lib.isList value
    then map rewriteFiles value
    else if lib.isAttrs value
    then lib.mapAttrs (_: rewriteFiles) value
    else value;
  configuration = format.generate "seerr.json" {
    version = 1;
    inherit (declarative) owner;
    settings = rewriteFiles declarative.settings;
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
      description = ''
        Authoritative settings. Objects of the form { file = "/absolute/path"; }
        are automatically loaded through systemd credentials and rewritten to
        service-readable paths. Never put secret values directly in settings.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && declarative.enable) {
    assertions = [
      {
        assertion = lib.all (lib.hasPrefix "/") secretFiles;
        message = "Seerr declarative secret file references must use absolute paths.";
      }
    ];
    systemd.services.seerr = {
      environment.SEERR_CONFIG_FILE = configuration;
      restartTriggers = [configuration];
      serviceConfig.LoadCredential = map (file: "${credentialName file}:${file}") secretFiles;
    };
  };
}
