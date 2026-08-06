{config, lib, ...}: {
  services.jellyseerr = {
    enable = true;
  };

  services.nginx.virtualHosts."requests.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.jellyseerr.port}";
      proxyWebsockets = true;
    };
  };


  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/jellyseerr";
      user = "jellyseerr";
      group = "jellyseerr";
      mode = "0700";
    }];
  };

  # Disable DynamicUser
  systemd.services.seerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "jellyseerr";
    Group = lib.mkForce "jellyseerr";
  };
  users = {
    users.jellyseerr = {
      home = "/var/lib/jellyseerr";
      group = "jellyseerr";
      isSystemUser = true;
    };
    groups.jellyseerr = {};
  };
}
