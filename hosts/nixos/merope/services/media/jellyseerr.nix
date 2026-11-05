{
  config,
  pkgs,
  ...
}: {
  services.seerr = {
    enable = true;
    package = pkgs.seerr-oidc;
  };

  sops.secrets.authentik-seerr-client-secret = {
    sopsFile = ../../secrets.yaml;
    restartUnits = ["seerr.service"];
  };

  systemd.services.seerr = {
    serviceConfig.LoadCredential = ["oidc-secret:${config.sops.secrets.authentik-seerr-client-secret.path}"];
    preStart = ''
      umask 077
      ${pkgs.python3}/bin/python ${./seerr-prepare.py} ${config.services.seerr.configDir}
    '';
  };

  services.nginx.virtualHosts."requests.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.seerr.port}";
      proxyWebsockets = true;
    };
  };

  environment.persistence."/persist".directories = [
    "/var/lib/private/jellyseerr"
  ];
}
