{pkgs, ...}: {
  imports = [
    ./global
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/rgb
    ./features/productivity
    ./features/productivity/accounts/personal.nix
    ./features/productivity/accounts/usp.nix
    ./features/productivity/accounts/mgc.nix
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

  services.kanshi.settings = [
    {
      profile.outputs = [
        {
          criteria = "LG Electronics LG ULTRAWIDE 0x01010101";
          mode = "2560x1080@60Hz";
          position = "0,0";
          scale = 1.0;
        }
        {
          criteria = "LG Electronics LG FULL HD 211AZDB4S394";
          mode = "1920x1080@60Hz";
          position = "2560,0";
          scale = 1.0;
        }
      ];
    }
  ];
}
