{pkgs, ...}: {
  imports = [
    ./global
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/rgb
    ./features/productivity
    ./features/productivity/accounts/personal.nix
    ./features/productivity/accounts/usp.nix
    ./features/pass
    ./features/games
    ./features/games/shadps4.nix
    ./features/ai
  ];

  accounts = {
    email.accounts.personal.primary = true;
    calendar.accounts.personal.primary = true;
  };

  # Pink-red (0°)
  wallpaper = pkgs.wallpapers.aenami-dawn;

  #  ------   -----   ------
  # | DP-3 | | DP-1| | DP-2 |
  #  ------   -----   ------
  monitors = [
    {
      name = "DP-1";
      width = 2560;
      height = 1080;
      workspace = "1";
      primary = true;
    }
    {
      name = "DP-2";
      width = 1920;
      height = 1080;
      position = "auto-right";
      workspace = "2";
    }
  ];
}
