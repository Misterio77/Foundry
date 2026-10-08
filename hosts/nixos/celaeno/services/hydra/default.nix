{
  pkgs,
  config,
  outputs,
  ...
}: let
  hydraUser = config.users.users.hydra.name;
  hydraGroup = config.users.users.hydra.group;
  builderToken = config.sops.secrets.hydra-queue-runner-token.path;
  restrictedAccess = ''
    allow 127.0.0.1;
    allow ::1;
    allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
    allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
    deny all;
  '';
in {
  imports = [../../../common/optional/hydra-builder.nix];

  # https://github.com/NixOS/nix/issues/4178#issuecomment-738886808
  systemd.services.hydra-evaluator.environment.GC_DONT_GC = "true";
  systemd.sockets.hydra-queue-runner-grpc.socketConfig.BindIPv6Only = "both";
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    config.services.hydra.queueRunner.grpc.port
  ];

  services = {
    hydra = {
      enable = true;
      package = pkgs.hydra;
      hydraURL = "https://hydra.m7.rs";
      notificationSender = "hydra@m7.rs";
      listenHost = "localhost";
      smtpHost = "localhost";
      useSubstitutes = true;
      queueRunner = {
        grpc.address = "[::]";
        settings = {
          maxUnsupportedTimeInS = 30;
          tokenPaths = [builderToken];
        };
      };
      extraConfig =
        /*
        xml
        */
        ''
          Include ${config.sops.secrets.hydra-gh-auth.path}
          allow_import_from_derivation = true
          ws_endpoint = wss://hydra.m7.rs/ws
          <githubstatus>
            jobs = .*
            useShortContext = true
          </githubstatus>
        '';
      extraEnv = {
        HYDRA_DISALLOW_UNFREE = "0";
      };
    };
    nginx.virtualHosts = {
      "hydra.m7.rs" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "~* ^/shield/([^\\s]*)".return = "302 https://img.shields.io/endpoint?url=https://hydra.m7.rs/$1/shield";
          "/" = {
            proxyPass = "http://localhost:${toString config.services.hydra.port}";
            extraConfig = restrictedAccess;
          };
          "= /ws" = {
            proxyPass = "http://${config.services.hydra.ws.bind.address}:${toString config.services.hydra.ws.bind.port}";
            proxyWebsockets = true;
            extraConfig = restrictedAccess;
          };
        };
      };
    };
  };
  users.users = {
    hydra-queue-runner.extraGroups = [hydraGroup];
    hydra-www.extraGroups = [hydraGroup];
  };
  sops.secrets = {
    hydra-gh-auth = {
      sopsFile = ../../secrets.yaml;
      owner = hydraUser;
      group = hydraGroup;
      mode = "0440";
    };
    hydra-queue-runner-token = {
      sopsFile = ../../../common/secrets.yaml;
      key = "hydra-builder-token";
      owner = "hydra-queue-runner";
      mode = "0400";
      reloadUnits = ["hydra-queue-runner.service"];
    };
  };

  environment.persistence = {
    "/persist".directories = [
      {
        directory = config.users.users.hydra.home;
        user = config.users.users.hydra.name;
        group = config.users.users.hydra.group;
        mode = "0700";
      }
    ];
  };
}
