{config, ...}: let
  domain = "feed.m7.rs";
  tailnetOnly = ''
    allow 127.0.0.1;
    allow ::1;
    allow ${config.services.headscale.settings.prefixes.v4};
    allow ${config.services.headscale.settings.prefixes.v6};
    deny all;
  '';
in {
  services = {
    freshrss = {
      enable = true;
      baseUrl = "https://${domain}";
      defaultUser = "gabriel";
      passwordFile = config.sops.secrets.freshrss-password.path;
      api.enable = true;
      virtualHost = domain;
    };

    nginx.virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/".extraConfig = tailnetOnly;
        "~ ^.+?\\.php(/.*)?$".extraConfig = tailnetOnly;
      };
    };
  };

  sops.secrets.freshrss-password = {
    sopsFile = ../secrets.yaml;
    owner = config.services.freshrss.user;
    group = config.users.users.${config.services.freshrss.user}.group;
  };

  environment.persistence."/persist".directories = [
    {
      directory = config.services.freshrss.dataDir;
      user = config.services.freshrss.user;
      group = config.users.users.${config.services.freshrss.user}.group;
      mode = "0750";
    }
  ];
}
