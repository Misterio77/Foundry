{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.sogo6;
  json = pkgs.formats.json {};
  systemConfig = json.generate "sogo6-system.json" {settings = cfg.systemSettings;};
  domainConfig = json.generate "sogo6-domain.json" {settings = cfg.domainSettings;};
  hardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    UMask = "0077";
    Restart = "on-failure";
    RestartSec = 5;
  };
  startApi = pkgs.writeShellScript "sogo6-api-start" ''
    set -eu
    export SOGO_P_VOUCHER_SECRET="$(< /var/lib/sogo6/voucher-key)"
    export SOGO_AES_ENC_KEY="$(< /var/lib/sogo6/encryption-key)"
    ${lib.getExe pkgs.jq} --rawfile secret "$CREDENTIALS_DIRECTORY/oidc-client-secret" \
      '.settings.AUTH_SETTINGS.SOGO_D_OPENID_CLIENT_SECRET = ($secret | rtrimstr("\n"))' \
      ${domainConfig} > "$RUNTIME_DIRECTORY/domain.json"
    exec ${lib.getExe cfg.package} --bind 127.0.0.1:${toString cfg.apiPort} \
      --workers 1 --timeout 120 --access-logfile /dev/null --no-control-socket
  '';
in {
  options.services.sogo6 = {
    enable = lib.mkEnableOption "native SOGo 6 with OIDC and direct DAV";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sogo6-server;
    };
    uiPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sogo6-ui;
    };
    publicUrl = lib.mkOption {type = lib.types.str;};
    logoutUrl = lib.mkOption {type = lib.types.str;};
    davUrl = lib.mkOption {type = lib.types.str;};
    oidcClientSecretFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime file containing the confidential OIDC client secret; never a store path.";
    };
    systemSettings = lib.mkOption {type = json.type;};
    domainSettings = lib.mkOption {type = json.type;};
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 13001;
    };
    uiPort = lib.mkOption {
      type = lib.types.port;
      default = 13000;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (lib.hasPrefix "https://") [cfg.publicUrl cfg.logoutUrl cfg.davUrl];
        message = "SOGo public, logout and DAV URLs must use HTTPS.";
      }
      {
        assertion = !(lib.hasPrefix builtins.storeDir cfg.oidcClientSecretFile);
        message = "The SOGo OIDC client secret must not enter the Nix store.";
      }
      {
        assertion = !((cfg.domainSettings.AUTH_SETTINGS or {}) ? SOGO_D_OPENID_CLIENT_SECRET);
        message = "Supply the SOGo OIDC secret through oidcClientSecretFile, not domainSettings.";
      }
    ];

    users.groups.sogo6 = {};
    users.users.sogo6 = {
      isSystemUser = true;
      group = "sogo6";
      extraGroups = ["redis-sogo6"];
    };
    services.postgresql = {
      enable = true;
      ensureDatabases = ["sogo6"];
      ensureUsers = [
        {
          name = "sogo6";
          ensureDBOwnership = true;
        }
      ];
    };
    services.redis.servers.sogo6 = {
      enable = true;
      port = 0;
      unixSocketPerm = 660;
      save = [];
      settings.appendonly = "no";
    };

    systemd.services.sogo6-api = {
      description = "SOGo 6 API";
      wantedBy = ["multi-user.target"];
      requires = ["postgresql.service" "postgresql-setup.service" "redis-sogo6.service"];
      wants = ["network-online.target"];
      after = ["postgresql.service" "postgresql-setup.service" "redis-sogo6.service" "network-online.target"];
      environment = {
        TZ = "UTC";
        SOGO_P_PUBLIC_BASE_URL = cfg.publicUrl;
        SOGO_OIDC_LOGOUT_URL = cfg.logoutUrl;
        SOGO_DAV_URL = cfg.davUrl;
        SOGO_P_DB_NAME = "sogo6";
        SOGO_P_DB_USER = "sogo6";
        SOGO_P_DB_PASS = "";
        SOGO_P_DB_HOST = "/run/postgresql";
        SOGO_P_REDIS_URL = "unix:///run/redis-sogo6/redis.sock?db=0";
        SOGO_INIT_SYSTEM_SETTINGS_PATH = systemConfig;
        SOGO_INIT_DOMAIN_SETTINGS_PATH = "/run/sogo6/domain.json";
        SOGO_FOUNDRY_AUTHORITATIVE_CONFIG = "1";
        SOGO_LOG_PATH = "/var/log/sogo6/server.log";
      };
      preStart = ''
        set -eu
        umask 077
        if [ ! -e /var/lib/sogo6/voucher-key ] || [ ! -e /var/lib/sogo6/encryption-key ]; then
          initialized="$(${lib.getExe' config.services.postgresql.package "psql"} -d sogo6 -Atc \
            "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema='public' AND table_name='sogo6_sogo_settings')")"
          if [ "$initialized" != f ]; then
            echo 'SOGo keys are missing for an initialized database; restore the matching keys.' >&2
            exit 1
          fi
        fi
        if [ ! -e /var/lib/sogo6/voucher-key ]; then
          ${lib.getExe pkgs.openssl} rand -hex 16 > /var/lib/sogo6/voucher-key.tmp
          mv /var/lib/sogo6/voucher-key.tmp /var/lib/sogo6/voucher-key
        fi
        if [ ! -e /var/lib/sogo6/encryption-key ]; then
          ${lib.getExe pkgs.openssl} rand -base64 32 > /var/lib/sogo6/encryption-key.tmp
          mv /var/lib/sogo6/encryption-key.tmp /var/lib/sogo6/encryption-key
        fi
        test -s /var/lib/sogo6/voucher-key
        test -s /var/lib/sogo6/encryption-key
      '';
      serviceConfig =
        hardening
        // {
          User = "sogo6";
          Group = "sogo6";
          StateDirectory = "sogo6";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "sogo6";
          RuntimeDirectoryMode = "0700";
          LogsDirectory = "sogo6";
          LogsDirectoryMode = "0700";
          LoadCredential = ["oidc-client-secret:${cfg.oidcClientSecretFile}"];
          ExecStart = startApi;
          ExecStartPost = pkgs.writeShellScript "sogo6-api-ready" ''
            exec ${lib.getExe pkgs.curl} --fail --silent --show-error \
              --retry 30 --retry-connrefused --retry-delay 1 --retry-max-time 60 --max-time 3 \
              --header ${lib.escapeShellArg "Host: ${lib.removePrefix "https://" cfg.publicUrl}"} \
              http://127.0.0.1:${toString cfg.apiPort}/api/user/v1/system --output /dev/null
          '';
        };
    };

    systemd.services.sogo6-ui = {
      description = "SOGo 6 web UI";
      wantedBy = ["multi-user.target"];
      after = ["sogo6-api.service"];
      environment = {
        HOSTNAME = "127.0.0.1";
        PORT = toString cfg.uiPort;
        TZ = "UTC";
        REACT_APP_API_BASE_URL = "/api/user/v1";
        SSE_ENABLED = "false";
      };
      serviceConfig =
        hardening
        // {
          DynamicUser = true;
          CacheDirectory = "sogo6-ui";
          BindPaths = ["/var/cache/sogo6-ui:${cfg.uiPackage}/share/sogo6-ui/.next/cache"];
          ExecStart = lib.getExe cfg.uiPackage;
        };
    };
  };
}
