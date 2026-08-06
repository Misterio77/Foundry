{pkgs, ...}: {
  imports = [
    ./generic.nix
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/pass
    ./features/ai
  ];

  targets.genericLinux = {
    enable = true;
    # System Manager owns /run/opengl-driver through nix-system-graphics.
    gpu.enable = false;
  };

  monitors = [
    {
      name = "eDP-1";
      width = 1920;
      height = 1080;
      workspace = "1";
      primary = true;
      scale = 1.25;
    }
  ];

  wallpaper = pkgs.wallpapers.deer-lunar-fantasy;
}
