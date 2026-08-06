{pkgs, config, ...}: let
  cfg = config.services.minecraft-servers.servers.gtnh;
in {
  networking.firewall = {
    allowedTCPPorts = [cfg.serverProperties.server-port];
    allowedUDPPorts = [cfg.serverProperties.server-port];
  };

  services.minecraft-servers.servers.gtnh = rec {
    enable = true;
    enableReload = true;
    package = pkgs.callPackage ./gtnh.nix { };
    jvmOpts = "-Xms6G -Xmx6G -Dfml.readTimeout=180";
    whitelist = import ../../whitelist.nix;
    serverProperties = {
      level-type = "rwg";
      difficulty = 3;
      spawn-protection = 1;
      server-port = 25565;
      online-mode = true;
      white-list = true;
      motd = "Greg\\u00f3rio T\\u00e9cnico: Novidades Horizontais";
      max-tick-time = 60000; # 1 minute
      level-seed = "4387134805370572030";
    };
    files = {
      config = "${package}/lib/config";
      serverutilities = "${package}/lib/serverutilities";
      "serverutilities/serverutilities.cfg" = ./configs/serverutilities.cfg;
      "config/JourneyMapServer/world.cfg" = ./configs/journeymap-world.cfg;
      "config/SpecialMobs.cfg" = ./configs/SpecialMobs.cfg;
      "dynmap/configuration.txt" = {
        format = pkgs.formats.yaml {};
        value = (import ./configs/dynmap.default.nix) // {
          webserver-port = 8123;
          deftemplatesuffix = "hires";
          defaultmap = "surface";
          defaultworld = "world";
        };
      };
    };
    symlinks = {
      "mods/bungeeforge-1.7.10.jar" = pkgs.fetchurl rec {
        pname = "bungeeforge";
        version = "1.0.6";
        url = "https://github.com/caunt/BungeeForge/releases/download/v${version}/bungeeforge-1.7.10.jar";
        hash = "sha256-Y10ExD0nn1pkjhrgsSq9eiww5+n0J5skoC2EetXCVGM=";
      };
      "mods/gtnh-web-map-0.3.45.jar" = pkgs.fetchurl rec {
        pname = "gtnh-web-map";
        version = "0.3.45";
        url = "https://github.com/GTNewHorizons/GTNH-Web-Map/releases/download/${version}/gtnh-web-map-${version}.jar";
        hash = "sha256-e9qt0egZSQxZHlfozfoGLIDbvyyy59df0pYkHSfMRAQ=";
      };
    };
  };

  services.nginx.virtualHosts."mc.m7.rs" = let
    dynmapCfg = cfg.files."dynmap/configuration.txt".value;
  in {
    forceSSL = true;
    enableACME = true;
    locations."/".proxyPass = "http://localhost:${toString dynmapCfg.webserver-port}";
  };
}
