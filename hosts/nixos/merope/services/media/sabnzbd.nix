{config, ...}: let
  sabnzbdDir = "/var/lib/${config.services.sabnzbd.stateDir}";
in {
  services.sabnzbd = {
    enable = true;
    configFile = null; # Explicitly migrate to `settings`
    settings = {
      misc = {
        host = "127.0.0.1";
        port = 6789;
        local_ranges = "127.0.0.1/32";
        inet_exposure = 2;
        download_dir = "/srv/media/incoming/usenet/downloading";
        complete_dir = "/srv/media/incoming/usenet/completed";
        log_dir = "${sabnzbdDir}/logs";
        admin_dir = "${sabnzbdDir}/admin";
        backup_dir = "${sabnzbdDir}/backup";
        permissions = 755; # Directories 0755, regular files 0644
        cache_limit = "1G";
        # Six servers x three rounds is a lot of round trips to spend before
        # concluding an article is gone; two rounds is enough
        max_art_tries = 2;
      };
      categories = {
        music.name = "music";
      };
      servers = {
        frugal = {
          enable = true;
          name = "frugal";
          displayname = "frugal";
          host = "sanews.frugalusenet.com";
          ssl = true;
          ssl_ciphers = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
          port = 563;
          username = "misterio";
          connections = 30;
          priority = 0;
        };
        frugal-secondary = {
          enable = true;
          name = "frugal-secondary";
          displayname = "frugal-secondary";
          host = "news.frugalusenet.com";
          ssl = true;
          ssl_ciphers = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
          port = 563;
          username = "misterio";
          connections = 15;
          priority = 0;
        };
        frugal-bonus = {
          enable = true;
          name = "frugal-bonus";
          displayname = "frugal-bonus";
          host = "bonus.frugalusenet.com";
          ssl = true;
          ssl_ciphers = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
          port = 563;
          username = "misterio";
          connections = 10;
          priority = 1;
        };
        eweka = {
          enable = true;
          name = "eweka";
          displayname = "eweka";
          host = "news.eweka.nl";
          ssl = true;
          ssl_ciphers = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
          port = 563;
          username = "043b11d25e1d9f6f";
          password = "@eweka-key";
          connections = 10;
          priority = 2;
        };
        blocknews = {
          enable = true;
          name = "blocknews";
          displayname = "blocknews";
          host = "sanews.blocknews.net";
          ssl = true;
          ssl_ciphers = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
          port = 563;
          username = "misterio";
          connections = 10;
          priority = 3;
        };
        blocknews-secondary = {
          enable = true;
          name = "blocknews";
          displayname = "blocknews";
          host = "usnews.blocknews.net";
          ssl = true;
          ssl_ciphers = "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305";
          port = 563;
          username = "misterio";
          connections = 10;
          priority = 3;
        };
      };
    };
    # TODO switch to secretValues after bumping nixpkgs
    secretFiles = [config.sops.templates.sabnzbd-secrets.path];
  };
  sops.templates.sabnzbd-secrets = {
    content = /*ini*/ ''
      [misc]
      api_key = ${config.sops.placeholder.sabnzbd-key}
      [servers]
      [[frugal]]
      password = ${config.sops.placeholder.frugalusenet-key}
      [[frugal-secondary]]
      password = ${config.sops.placeholder.frugalusenet-key}
      [[frugal-bonus]]
      password = ${config.sops.placeholder.frugalusenet-key}
      [[eweka]]
      password = ${config.sops.placeholder.eweka-key}
      [[blocknews]]
      password = ${config.sops.placeholder.blocknews-key}
      [[blocknews-secondary]]
      password = ${config.sops.placeholder.blocknews-key}
    '';
    owner = config.services.sabnzbd.user;
    group = config.services.sabnzbd.group;
    mode = "0600";
    restartUnits = ["sabnzbd.service"];
  };

  systemd.tmpfiles.settings.srv-media-incoming-usenet."/srv/media/incoming/usenet".d = {
    user = config.services.sabnzbd.user;
    group = config.services.sabnzbd.group;
    mode = "0770"; # So that others in the group (e.g. *arr) can move/hardlink completed files
  };

  systemd.services.sabnzbd.serviceConfig = {
    # A SIGTERM'd sabnzbd saves its queue and exits 0, so `on-failure` would
    # leave it dead after an out-of-memory kill
    Restart = "always";
    # Yield to playback and library scans; par2/unrar inherit this as children
    CPUWeight = 20;
    IOWeight = 20;
    # Registering only this unit for swap monitoring makes it the sole candidate
    # once swap passes oomd's 90% limit, so ranking by swap usage cannot pick a
    # service that is merely holding cold pages. Catches a runaway early; the
    # pressure rule on system.slice is the later, broader net.
    ManagedOOMSwap = "kill";
  };

  sops.secrets = {
    sabnzbd-key.sopsFile = ../../secrets.yaml;
    frugalusenet-key.sopsFile  = ../../secrets.yaml;
    blocknews-key.sopsFile  = ../../secrets.yaml;
    eweka-key.sopsFile  = ../../secrets.yaml;
  };

  environment.persistence = {
    "/persist".directories = [
      {
        directory = sabnzbdDir;
        user = config.services.sabnzbd.user;
        group = config.services.sabnzbd.group;
        mode = "0700";
      }
    ];
  };
}
