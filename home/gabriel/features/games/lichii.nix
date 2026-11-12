{
  pkgs,
  config,
  ...
}: {
  home.packages = [pkgs.lichii];

  programs.steam.config.nonSteamApps."Ocarina of Time" = {
    id = 2364296439;
    name = "The Legend of Zelda: Ocarina of Time";
    target = pkgs.lichii;
    startIn = config.home.homeDirectory;
    args = ["${config.xdg.dataHome}/eden/ROMs/ocarina-of-time.nup"];
    artwork = {
      cover = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/grid/2644a3967c43b879d262ec0d06de3801.png";
        hash = "sha256-amV1AYBlU5E34DV4P6lH3+d5bOFuapvaIiVrrpVnBiU=";
      };
      header = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/grid/834a44111486056b5bc0d74d0e7aa5d9.png";
        hash = "sha256-PMt43fouKBJxfKJGxvyNCu186zCIXzXdNA7wxdEV5Hk=";
      };
      hero = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/hero/e1557e72fd5a8da1b41dff46f228cf28.png";
        hash = "sha256-Xh1rp7NRQ84BDrAUKdxBSa5N2YTQg7HUcyfrbJXuRRk=";
      };
      icon = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/icon/a896144046a1b5bd6e3e034d00b4f73a.png";
        hash = "sha256-pSbLDAji9s/itHrfsxImQGyzuzXhWcK7oHx8AVK0pIw=";
      };
      logo = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/logo/373ca39d0a5c1dc1141f9f279d92280f.png";
        hash = "sha256-6Qh7KVJS0K5zwAepYApqMBSC6ENzoxbhH8o1N0Hdsm4=";
      };
    };
  };

  home.persistence = {
    "/persist".directories = [
      ".config/eden"
      ".local/share/eden"
    ];
  };
}
