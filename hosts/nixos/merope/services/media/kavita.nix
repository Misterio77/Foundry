{
  config,
  pkgs,
  ...
}: let
  cfg = config.services.kavita;
  tokenKeyFile = "${cfg.dataDir}/token-key";
in {
  services = {
    kavita = {
      enable = true;
      inherit tokenKeyFile;
      # JellySearch already occupies Kavita's default port 5000.
      settings.Port = 5001;
    };

    nginx.virtualHosts."books.m7.rs" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString cfg.settings.Port}";
        proxyWebsockets = true;
      };
    };
  };

  # Kavita needs a stable, machine-local signing key. Generate it once in the
  # persisted data directory before systemd loads it as a credential.
  systemd.services = {
    kavita-token = {
      description = "Generate Kavita token key";
      before = ["kavita.service"];
      requiredBy = ["kavita.service"];
      unitConfig.RequiresMountsFor = cfg.dataDir;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.user;
        ExecStart = pkgs.writeShellScript "generate-kavita-token" ''
          set -eu
          if [[ ! -s ${tokenKeyFile} ]]; then
            umask 077
            ${pkgs.coreutils}/bin/head -c 64 /dev/urandom \
              | ${pkgs.coreutils}/bin/base64 --wrap=0 > ${tokenKeyFile}
          fi
        '';
      };
    };

    kavita.serviceConfig = {
      CPUWeight = 50;
      IOWeight = 50;
      ReadOnlyPaths = ["/srv/media/books"];
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = cfg.dataDir;
      user = cfg.user;
      group = cfg.user;
      mode = "0700";
    }
  ];
}
