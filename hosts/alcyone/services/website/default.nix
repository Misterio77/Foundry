{pkgs, ...}: let
  website = pkgs.website;
  pgpKey = ../../../../home/gabriel/pgp.asc;
  sshKey = ../../../../home/gabriel/ssh.pub;
  redir = {
    forceSSL = true;
    enableACME = true;
    locations."/".return = "301 https://gsfontes.com$request_uri";
  };
  days = n: (hours n) * 24;
  hours = n: (minutes n) * 60;
  minutes = n: n * 60;
in {
  imports = [
    ./shortner.nix
  ];

  services.nginx.virtualHosts = {
    "gsfontes.com" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          root = "${website}/public";
          extraConfig = ''
            add_header Cache-Control "max-age=${toString (minutes 5)}, stale-while-revalidate=${toString (minutes 15)}";
          '';
        };
        "/assets/" = {
          root = "${website}/public";
          extraConfig = ''
            add_header Cache-Control "max-age=${toString (hours 1)}, stale-while-revalidate=${toString (days 30)}";
          '';
        };
        "/.well-known/caldav".return = "302 https://dav.m7.rs";
        "/.well-known/carddav".return = "302 https://dav.m7.rs";

        "=/nix" = {
          # Script to download static nix
          alias = ./scripts/nix-installer.sh;
        };

        "=/setup-gpg" = {
          alias = ./scripts/setup-gpg.sh;
        };

        "=/7088C7421873E0DB97FF17C2245CAB70B4C225E9.asc".alias = pgpKey;
        "=/pgp.asc".alias = pgpKey;
        "=/pgp".alias = pgpKey;
        "=/ssh.pub".alias = sshKey;
        "=/ssh".alias = sshKey;
      };
    };
    "m7.rs" = redir;
    "misterio.me" = redir;
  };
}
