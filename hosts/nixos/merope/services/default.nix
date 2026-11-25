{
  imports = [
    ../../common/optional/nginx.nix
    ../../common/optional/mysql.nix
    ../../common/optional/postgres.nix

    ./backups-repo.nix
    ./git-lfs.nix
    ./media
    ./immich.nix
    ./redlib.nix
  ];
}
