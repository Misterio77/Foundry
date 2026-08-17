{
  config,
  pkgs,
  ...
}: {
  services.seerr = {
    enable = true;
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
