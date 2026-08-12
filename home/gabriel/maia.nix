{pkgs, ...}: {
  imports = [
    ./global
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/productivity
    ./features/productivity/accounts/personal.nix
    ./features/productivity/accounts/usp.nix
    ./features/pass
    ./features/games
    ./features/ai
  ];

  accounts = {
    email.accounts.personal.primary = true;
    calendar.accounts.personal.primary = true;
  };

  # Periwinkle (280°)
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
