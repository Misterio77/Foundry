{pkgs, ...}: {
  imports = [
    ./generic.nix
    ./features/desktop/hyprland
    ./features/productivity
    ./features/pass
    ./features/ai
  ];

  targets.genericLinux = {
    enable = true;
    # System Manager owns /run/opengl-driver through nix-system-graphics.
    gpu.enable = false;
  };

  wallpaper = pkgs.wallpapers.deer-lunar-fantasy;
}
