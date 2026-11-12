{
  pkgs,
  config,
  ...
}: {
  home.packages = [pkgs.shadps4];

  programs.steam.config.nonSteamApps."Bloodborne" = {
    id = 3621450659;
    target = pkgs.shadps4;
    startIn = config.home.homeDirectory;
    args = ["-g" "${config.xdg.dataHome}/shadPS4/ROMs/CUSA03173/eboot.bin"];
    artwork = {
      cover = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/grid/021399af062379408df9c358a1a83cdb.png";
        hash = "sha256-aK7Qs2l56/x275O0Vm1FAHt8bk6qMDiU8onjL6sdelU=";
      };
      header = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/grid/4a492541bbd7a0d1aaebcafb28cee29a.jpg";
        hash = "sha256-O22fIrisIdbGxAY2GN0QWGQYQDTf0QsfljGTB4+2VyY=";
      };
      hero = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/hero/f20fd1e8deb34b1bc57a3146f2511eb2.png";
        hash = "sha256-I16aEi0X0IYPohDbgbHp4wp1y64HeXLNXyo3ns2DJ2I=";
      };
      icon = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/icon/b0b14130d4056e057f7234fc60a8bd58.png";
        hash = "sha256-yysWy5fWJ3qsWJXGqVXTXCPyyX5RF1Mn0dgR2giWmWk=";
      };
      logo = pkgs.fetchurl {
        url = "https://cdn2.steamgriddb.com/logo/e0f8753690e64e6d42d9b56fbad30faf.png";
        hash = "sha256-lOkNLn9o3XiFh0JsD3CMuMze2o0/MEyQA7CPfp07X+A=";
      };
    };
  };

  home.persistence = {
    "/persist".directories = [".local/share/shadPS4"];
  };
}
