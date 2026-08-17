{
  config,
  lib,
  ...
}: {
  users.users = {
    # Allow calibre to write to readarr-managed library
    calibre-server.extraGroups = [config.services.readarr.group];
    calibre-web.extraGroups = [config.services.calibre-server.group config.services.readarr.group];
  };

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
      UMask = "0002";
    };

    calibre-web.serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
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
