{config, outputs, ...}: {
  services.radarr = {
    enable = true;
    settings = {
      server.port = 8687;
    };
  };

  services.nginx.virtualHosts."radarr.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.radarr.settings.server.port}";
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


  # Add radarr to deluge's and nzbget's groups
  # Make sure radarr can hard-link their files
  users.users.radarr.extraGroups = [
    config.users.users.deluge.group
    config.services.sabnzbd.group
  ];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = config.services.radarr.dataDir;
        user = config.services.radarr.user;
        group = config.services.radarr.group;
        mode = "0700";
      }
    ];
  };

  systemd.tmpfiles.settings.srv-media-movies."/srv/media/movies".d = {
    user = config.services.radarr.user;
    group = config.services.radarr.group;
    mode = "0755";
  };

  systemd.services.radarr.serviceConfig.Nice = 10;
}
