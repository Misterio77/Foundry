{
  imports = [
    ../../common/optional/nginx.nix
    ../../common/optional/mysql.nix
    ../../common/optional/postgres.nix

    ./grafana
    ./files-server.nix
    ./git-remote.nix
    ./headscale.nix
    ./mail.nix
    ./prometheus.nix
    ./radicale.nix
    ./firefly.nix
    ./lumis.nix

    # Disabled for now
    # ./cgit
    ./website
  ];
}
