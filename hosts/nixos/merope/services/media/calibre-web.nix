{
  config,
  lib,
  ...
}: {
  # Calibre Content Server maintains Readarr's library. Calibre-Web consumes
  # the resulting database and files read-only, like Jellyfin.
  users.users.calibre-server.extraGroups = [config.services.readarr.group];

  services = {
    calibre-server = {
      enable = true;
      libraries = ["/srv/media/books"];
      # Readarr connects locally and uses the Content Server to update the
      # Calibre database without racing direct metadata.db writes.
      extraFlags = ["--enable-local-write"];
    };

    calibre-web = {
      enable = true;
      options.calibreLibrary = lib.head config.services.calibre-server.libraries;
    };

    nginx.virtualHosts."books.m7.rs" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.calibre-web.listen.port}";
        proxyWebsockets = true;
      };
    };
  };

  systemd.services = {
    calibre-server.serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
      # Calibre-Web reads the library through the world-readable bits.
      UMask = "0002";
    };

    calibre-web.serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
      ReadWritePaths = lib.mkForce [];
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/calibre-web";
      user = config.services.calibre-web.user;
      group = config.services.calibre-web.group;
      mode = "0700";
    }
  ];
}
