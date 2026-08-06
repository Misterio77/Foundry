{config, outputs, ...}: {
  services.lidarr = {
    enable = true;
    settings = {
      server.port = 8686;
    };
  };

  services.nginx.virtualHosts."lidarr.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.lidarr.settings.server.port}";
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

  # Add lidarr to deluge's and nzbget's groups
  # Make sure lidarr can hard-link their files
  users.users.lidarr.extraGroups = [
    config.users.users.deluge.group
    config.services.sabnzbd.group
  ];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = config.services.lidarr.dataDir;
        user = config.services.lidarr.user;
        group = config.services.lidarr.group;
        mode = "0700";
      }
    ];
  };

  systemd.tmpfiles.settings.srv-media-music."/srv/media/music".d = {
    user = config.services.lidarr.user;
    group = config.services.lidarr.group;
    mode = "0755";
  };

  systemd.services.lidarr.serviceConfig.Nice = 10;
}
