{pkgs, ...}: let
  website = pkgs.website;
  pgpKey = ../../../../../home/gabriel/pgp.asc;
  sshKey = ../../../../../home/gabriel/ssh.pub;
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
      root = "${website}/public";
      locations = {
        "/".extraConfig = ''
          add_header Cache-Control "max-age=${toString (minutes 5)}, stale-while-revalidate=${toString (minutes 15)}";
        '';
        "/assets/".extraConfig = ''
          add_header Cache-Control "max-age=${toString (hours 1)}, stale-while-revalidate=${toString (days 30)}";
        '';
        "=/404.html".extraConfig = ''
          internal;
        '';
        "/.well-known/caldav".return = "302 https://dav.m7.rs";
        "/.well-known/carddav".return = "302 https://dav.m7.rs";

        "=/7088C7421873E0DB97FF17C2245CAB70B4C225E9.asc".alias = pgpKey;
        "=/pgp.asc".alias = pgpKey;
        "=/pgp".alias = pgpKey;
        "=/ssh.pub".alias = sshKey;
        "=/ssh".alias = sshKey;
      };
      extraConfig = ''
        error_page 404 /404.html;
      '';
    };
    "m7.rs" = redir;
    "misterio.me" = redir;
  };
}
