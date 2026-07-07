{config, outputs, ...}: {
  services.bazarr = {
    enable = true;
    listenPort = 8689;
  };

  services.nginx.virtualHosts."bazarr.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.bazarr.listenPort}";
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

  # Add bazarr to sonarr and radarr groups
  # So that it can write to the library dirs
  users.users.bazarr.extraGroups = [
    config.services.sonarr.group
    config.services.radarr.group
  ];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = config.services.bazarr.dataDir;
        user = config.services.bazarr.user;
        group = config.services.bazarr.group;
        mode = "0700";
      }
    ];
  };

  systemd.services.bazarr.serviceConfig.Nice = 10;
}
