{config, ...}: {
  services.sabnzbd = {
    enable = true;
    configFile = config.sops.templates.sabnzbd-config.path;
  };
  sops.templates.sabnzbd-config = {
    content = /*ini*/ ''
      [misc]
      host = 127.0.0.1
      port = 6789
      local_ranges = 127.0.0.1/32
      api_key = ${config.sops.placeholder.sabnzbd-key}
      inet_exposure = 2
      download_dir = /srv/media/incoming/usenet/downloading
      complete_dir = /srv/media/incoming/usenet/completed
      log_dir = /var/lib/sabnzbd/logs
      admin_dir = /var/lib/sabnzbd/admin
      backup_dir = /var/lib/sabnzbd/backup
      permissions = 770
      pause_on_post_processing = 1

      [categories]
      [[music]]
      name = music

      # This Pi's Cortex-A72 has no ARMv8 crypto extensions, so TLS is decrypted
      # in software: AES-256-GCM manages 53 MB/s per core against 208 MB/s for
      # ChaCha20-Poly1305. Every provider defaults to AES and all six accept
      # ChaCha20, so asking for it moves most of a core off decryption.
      #
      # Setting ssl_ciphers makes SABnzbd cap the connection at TLS 1.2, because
      # Python does not expose SSL_CTX_set_ciphersuites() for the 1.3 suites.
      # ECDHE keeps forward secrecy and ChaCha20-Poly1305 is the same AEAD that
      # 1.3 would use, so the downgrade costs an extra handshake round trip and
      # an unencrypted certificate, nothing more. Drop these lines once upstream
      # can select 1.3 ciphersuites.
      [servers]
      [[frugal]]
      enable = 1
      name = frugal
      host = sanews.frugalusenet.com
      ssl = 1
      ssl_ciphers = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
      port = 563
      username = misterio
      password = ${config.sops.placeholder.frugalusenet-key}
      connections = 150
      priority = 0
      [[frugal-secondary]]
      enable = 1
      name = frugal-secondary
      host = news.frugalusenet.com
      ssl = 1
      ssl_ciphers = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
      port = 563
      username = misterio
      password = ${config.sops.placeholder.frugalusenet-key}
      connections = 75
      priority = 0
      [[frugal-bonus]]
      enable = 1
      name = frugal-bonus
      host = bonus.frugalusenet.com
      ssl = 1
      ssl_ciphers = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
      port = 563
      username = misterio
      password = ${config.sops.placeholder.frugalusenet-key}
      connections = 50
      priority = 1
      [[eweka]]
      enable = 1
      name = eweka
      host = news.eweka.nl
      ssl = 1
      ssl_ciphers = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
      port = 563
      username = 043b11d25e1d9f6f
      password = ${config.sops.placeholder.eweka-key}
      connections = 50
      priority = 2
      [[blocknews]]
      enable = 1
      name = blocknews
      host = sanews.blocknews.net
      ssl = 1
      ssl_ciphers = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
      port = 563
      username = misterio
      password = ${config.sops.placeholder.blocknews-key}
      connections = 50
      priority = 3
      [[blocknews-secondary]]
      enable = 1
      name = blocknews-secondary
      host = usnews.blocknews.net
      ssl = 1
      ssl_ciphers = ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
      port = 563
      username = misterio
      password = ${config.sops.placeholder.blocknews-key}
      connections = 50
      priority = 3
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

  sops.secrets = {
    sabnzbd-key.sopsFile = ../../secrets.yaml;
    frugalusenet-key.sopsFile  = ../../secrets.yaml;
    blocknews-key.sopsFile  = ../../secrets.yaml;
    eweka-key.sopsFile  = ../../secrets.yaml;
  };
}
