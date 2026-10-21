{config, ...}: {
  services.nginx.virtualHosts = {
    "files.m7.rs" = {
      forceSSL = true;
      enableACME = true;
      serverAliases = ["f.m7.rs"];
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow ${config.services.headscale.settings.prefixes.v4};
        allow ${config.services.headscale.settings.prefixes.v6};
        deny all;
      '';
      locations."/" = {
        root = "/srv/files";
      };
    };
  };
}
