{pkgs}:
pkgs.lib.listToAttrs (
  map (wallpaper: {
    inherit (wallpaper) name;
    value = pkgs.fetchurl {
      inherit (wallpaper) sha256;
      name = "${wallpaper.name}.${wallpaper.ext}";
      url = "https://i.imgur.com/${wallpaper.id}.${wallpaper.ext}";
    };
  }) (pkgs.lib.importJSON ./list.json)
)
