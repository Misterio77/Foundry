{config, lib, outputs, ...}: {
  services.prowlarr = {
    enable = true;
    settings = {
      server.port = 8685;
    };
  };

  services.nginx.virtualHosts."prowlarr.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.prowlarr.settings.server.port}";
      proxyWebsockets = true;
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
        allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
        deny all;
      '';
    };
  };


  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/prowlarr";
      user = "prowlarr";
      group = "prowlarr";
      mode = "0700";
    }];
  };

  # Disable DynamicUser
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "prowlarr";
    Group = lib.mkForce "prowlarr";
    Nice = 10;
  };
  users = {
    users.prowlarr = {
      home = "/var/lib/prowlarr";
      group = "prowlarr";
      isSystemUser = true;
    };
    groups.prowlarr = {};
  };
}
