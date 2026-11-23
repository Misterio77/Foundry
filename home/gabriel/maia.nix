{pkgs, ...}: {
  imports = [
    ./global
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/productivity
    ./features/productivity/accounts/personal.nix
    ./features/productivity/accounts/usp.nix
    ./features/productivity/accounts/mgc.nix
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

  services.kanshi.settings = [
    {
      profile.outputs = [
        {
          criteria = "eDP-1";
          mode = "2880x1920@120Hz";
          scale = 2.0;
        }
      ];
    }
  ];
}
