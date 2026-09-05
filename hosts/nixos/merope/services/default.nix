{
  imports = [
    ../../common/optional/nginx.nix
    ../../common/optional/mysql.nix
    ../../common/optional/postgres.nix

    ./backups-repo.nix
    ./media
    ./immich.nix
  ];
}
