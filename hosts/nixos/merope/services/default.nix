{
  imports = [
    ../../common/optional/nginx.nix
    ../../common/optional/mysql.nix
    ../../common/optional/postgres.nix

    ./authentik-ldap.nix
    ./backups-repo.nix
    ./media
    ./immich.nix
  ];
}
