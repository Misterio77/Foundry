{
  config,
  outputs,
  ...
}: {
  services.readarr = {
    enable = true;
    settings.server.port = 8787;
  };

  services.nginx.virtualHosts."readarr.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.readarr.settings.server.port}";
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

  # Readarr needs access to the download clients' files for imports.
  users.users.readarr.extraGroups = [
    config.users.users.deluge.group
    config.services.sabnzbd.group
  ];

  environment.persistence."/persist".directories = [
    {
      directory = config.services.readarr.dataDir;
      user = config.services.readarr.user;
      group = config.services.readarr.group;
      mode = "0700";
    }
  ];

  # Readarr owns the library; Calibre Content Server writes through Readarr's
  # group, while read-only consumers use the world-readable bits.
  systemd.tmpfiles.settings.srv-media-books."/srv/media/books".d = {
    user = config.services.readarr.user;
    group = config.services.readarr.group;
    mode = "2775";
  };

  systemd.services.readarr = {
    bindsTo = ["srv-media.mount"];
    after = ["srv-media.mount"];
    unitConfig.ConditionPathIsMountPoint = "/srv/media";
    serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
    };
  };
}
