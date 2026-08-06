{config, ...}: {
  services.deluge = {
    enable = true;
    declarative = true;
    authFile = config.sops.secrets.deluge-accounts.path;
    config = {
      enabled_plugins = ["Label"];
      copy_torrent_file = true;
      move_completed = true;
      torrentfiles_location = "/srv/torrents/files";
      download_location = "/srv/torrents/downloading";
      move_completed_path = "/srv/torrents/completed";
      dont_count_slow_torrents = true;
      max_active_seeding = -1;
      max_active_limit = -1;
      max_active_downloading = 8;
      max_connections_global = -1;
      # Daemon on 58846
      allow_remote = true;
      daemon_port = 58846;
      # Listen on 6880 only
      random_port = false;
      listen_ports = [
        6880
        6880
      ];
      # Outgoing is random
      random_outgoing_ports = true;
    };
    # Publicly opens listen_ports only
    openFirewall = true;
    web = {
      enable = true;
      port = 8112;
    };
  };

  # Make daemon available on tailnet
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      config.services.deluge.config.daemon_port
    ];
  };

  sops.secrets.deluge-accounts = {
    sopsFile = ../../secrets.yaml;
    owner = config.users.users.deluge.name;
    group = config.users.users.deluge.group;
    mode = "0600";
  };

  environment.persistence = {
    "/persist".directories = [
      {
        directory = config.services.deluge.dataDir;
        user = config.services.deluge.user;
        group = config.services.deluge.group;
        mode = "0700";
      }
    ];
  };

  systemd.tmpfiles.settings.srv-torrents."/srv/torrents".d = {
    user = config.services.deluge.user;
    group = config.services.deluge.group;
    mode = "0770"; # So that others in the group (e.g. *arr) can move/hardlink completed torrents
  };
}
