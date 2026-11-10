{
  config,
  pkgs,
  ...
}: let
  cfg = config.services.sogo6;
  localHosts = pkgs.writeText "sogo6-hosts" ''
    127.0.0.1 localhost mail.m7.rs dav.m7.rs auth.m7.rs
    ::1 localhost
  '';
in {
  sops.secrets.authentik-sogo-client-secret = {
    sopsFile = ../secrets.yaml;
    restartUnits = ["sogo6-api.service"];
  };

  services.sogo6 = {
    enable = true;
    publicUrl = "https://mail.m7.rs";
    logoutUrl = "https://auth.m7.rs/application/o/sogo/end-session/";
    davUrl = "https://dav.m7.rs/";
    oidcClientSecretFile = config.sops.secrets.authentik-sogo-client-secret.path;
    systemSettings.SYSTEM_SETTINGS = {
      SOGO_S_DO_DOMAIN = false;
      SOGO_S_KNOWN_DOMAIN = ["m7.rs"];
      SOGO_S_REJECT_UNKNOWN_DOMAIN = true;
      SOGO_S_DOMAINLESS_LOGIN = false;
    };
    domainSettings = {
      USER_SOURCE = {};
      AUTH_SETTINGS = {
        SOGO_D_AUTH_TYPE = "openid";
        SOGO_D_OPENID_CONFIG_URL = "https://auth.m7.rs/application/o/sogo/.well-known/openid-configuration";
        SOGO_D_OPENID_CLIENT_NAME = "sogo";
        SOGO_D_OPENID_SCOPE = "openid profile mail dav ak_proxy offline_access";
        SOGO_D_OPENID_EMAIL = "mail_account";
        SOGO_D_OPENID_ALLOW_REDIRECT = [cfg.publicUrl];
        SOGO_D_OPENID_REFRESH_ENABLE = true;
        SOGO_D_OPENID_TOKEN_CHECK_INTERVAL = 0;
        SOGO_D_OPENID_FETCH_USER_PROFILE = true;
        SOGO_D_OPENID_ENDSESSION_ENABLED = true;
        SOGO_D_LOGIN_MFA = false;
        SOGO_D_PWD_CHANGE_ENABLED = false;
        SOGO_D_PWD_RECOVERY = false;
      };
      MAIL_SETTINGS = {
        SOGO_D_MAIL_SERVER_TYPE = "imap";
        SOGO_D_IMAP_SERVER = "mail.m7.rs";
        SOGO_D_IMAP_PORT = 993;
        SOGO_D_IMAP_ENCRYPTION = "SSL/TLS";
        SOGO_D_IMAP_AUTH_MECH = "xoauth2";
        SOGO_D_MAIL_OUTGOING_TYPE = "smtp";
        SOGO_D_SMTP_SERVER = "mail.m7.rs";
        SOGO_D_SMTP_PORT = 465;
        SOGO_D_SMTP_ENCRYPTION = "SSL/TLS";
        SOGO_D_SMTP_AUTH_MECH = "xoauth2";
        SOGO_D_MAIL_INBOX = "INBOX";
        SOGO_D_MAIL_SENT = "Sent";
        SOGO_D_MAIL_DRAFT = "Drafts";
        SOGO_D_MAIL_JUNK = "Junk";
        SOGO_D_MAIL_TRASH = "Trash";
        SOGO_D_MAIL_CHECK_FROM = true;
        SOGO_D_MAIL_FILTERING_ENABLED = false;
        SOGO_D_VACATION_ENABLED = false;
        SOGO_D_FORWARD_ENABLED = false;
        SOGO_D_NOTIFY_ENABLED = false;
      };
      USER_MODULE_SETTINGS = {
        SOGO_D_MODULE_ACCESS = ["mail" "calendar" "contact"];
        SOGO_D_EAS_ACCESS = false;
        SOGO_D_ALLOW_EXT_MAIL_ACCOUNT = false;
        SOGO_D_ALLOW_EXT_AVATAR = false;
        SOGO_D_FOLDER_DISABLE_SHARING = ["mail" "calendar" "contact"];
        SOGO_D_FOLDER_DISABLE_SHARING_ANY_AUTH = ["mail" "calendar" "contact"];
        SOGO_D_FOLDER_DISABLE_EXPORT = ["calendar" "contact"];
      };
      CALENDAR_CONTACT_SETTINGS = {
        SOGO_D_CALDAV_ENABLED = true;
        SOGO_D_CARDAV_ENABLED = true;
        SOGO_D_CALDAV_PUBLIC_ACCESS_ENABLE = false;
        SOGO_D_CARDAV_PUBLIC_ACCESS_ENABLE = false;
        SOGO_D_CALENDAR_PUBLIC_LINK_ENABLED = false;
        SOGO_D_REMINDER_ALLOW_MAIL = false;
        SOGO_D_JITSI_LINK_ENABLED = false;
      };
    };
  };

  # Keep local TLS hostname verification without depending on tailnet DNS for this host's own services.
  systemd.services.sogo6-api = {
    after = ["nginx.service" "authentik.service"];
    serviceConfig.BindReadOnlyPaths = ["${localHosts}:/etc/hosts"];
  };
  services.nginx.virtualHosts."mail.m7.rs" = {
    forceSSL = true;
    locations."/api/" = {
      proxyPass = "http://127.0.0.1:${toString cfg.apiPort}";
      extraConfig = ''
        access_log off;
        error_log /dev/null crit;
        proxy_read_timeout 130s;
        proxy_buffering off;
      '';
    };
    locations."/".proxyPass = "http://127.0.0.1:${toString cfg.uiPort}";
  };

  services.postgresqlBackup.databases = ["sogo6"];
  services.borgbackup.jobs.alcyone.paths = ["/var/lib/sogo6"];
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/sogo6";
      user = "sogo6";
      group = "sogo6";
      mode = "0700";
    }
  ];
}
