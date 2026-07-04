{pkgs, ...}: {
  imports = [
    ./global
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/productivity
    ./features/pass
    ./features/games
    ./features/pi
  ];

  # Purple
  wallpaper = pkgs.wallpapers.deer-lunar-fantasy;

  monitors = [
    {
      name = "eDP-1";
      width = 2880;
      height = 1920;
      workspace = "1";
      primary = true;
      refreshRate = 120;
      scale = 2.0;
    }
  ];
}
