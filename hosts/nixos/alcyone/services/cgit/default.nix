{pkgs, ...}: let
  cgit = pkgs.cgit-pink.overrideAttrs (_: {
    pname = "scgit";
    version = "0.1";
    src = pkgs.fetchFromSourcehut {
      owner = "~misterio";
      repo = "scgit";
      rev = "2cd05c95827fb94740e876733dc6f7fe88340de2";
      sha256 = "sha256-95mRJ3ZCSkLHqehFQdwM2BY0h+YDhohwpnRiF6/lZtA=";
    };
  });

  compileSass = file:
    pkgs.runCommand "sass" {buildInputs = [pkgs.sass];} ''
      sass ${file} > $out
    '';
  partials = "${pkgs.website}/public/cgit_partials";
in {
  services = {
    nginx.virtualHosts."m7.rs" = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "=/git/style.css" = {
          alias = compileSass ./cgit.scss;
        };
        "=/git".return = "301 https://m7.rs/git/";
        "/git/" = {
          root = "${cgit}/cgit";
          extraConfig = ''
            rewrite ^/git/(.*) /$1 break;
            include ${pkgs.nginx}/conf/uwsgi_params;
            uwsgi_modifier1 9;
            uwsgi_pass unix:/run/uwsgi/cgit.sock;
          '';
        };
      };
    };
    uwsgi.instance.vassals.cgit = {
      type = "normal";
      master = "true";
      socket = "/run/uwsgi/cgit.sock";
      procname-master = "uwsgi cgit";
      plugins = ["cgi"];
      cgi = "${cgit}/cgit/cgit.cgi";
    };
  };

  systemd.services.create-cgit-cache = {
    description = "Create cache directory for cgit";
    enable = true;
    wantedBy = ["uwsgi.service"];
    serviceConfig = {
      type = "oneshot";
    };
    script = ''
      mkdir -p /run/cgit
      chown -R nginx:nginx /run/cgit
    '';
  };

  environment.etc."cgitrc".text = ''
    virtual-root=/git/
    remove-suffix=1

    cache-size=1000
    cache-root=/run/cgit

    root-title=Git
    root-desc=This is a cgit mirror for some of my projects. You might want to check them out on github (github.com/misterio77) instead.

    enable-http-clone=1
    noplainemail=1
    enable-index-owner=0

    enable-git-config=1

    css=/git/style.css
    head-include=${partials}/head.html
    nav-include=${partials}/nav.html

    readme=:README.md
    readme=:readme.md
    readme=:README.mkd
    readme=:readme.mkd
    readme=:README.rst
    readme=:readme.rst
    readme=:README.html
    readme=:readme.html
    readme=:README.htm
    readme=:readme.htm
    readme=:README.txt
    readme=:readme.txt
    readme=:README
    readme=:readme
    readme=:INSTALL.md
    readme=:install.md
    readme=:INSTALL.mkd
    readme=:install.mkd
    readme=:INSTALL.rst
    readme=:install.rst
    readme=:INSTALL.html
    readme=:install.html
    readme=:INSTALL.htm
    readme=:install.htm
    readme=:INSTALL.txt
    readme=:install.txt
    readme=:INSTALL
    readme=:install

    source-filter=${cgit}/lib/cgit/filters/syntax-highlighting.py
    about-filter=${cgit}/lib/cgit/filters/about-formatting.sh
    snapshots=tar.gz zip

    scan-path=/srv/git
    enable-git-config=1
  '';
}
