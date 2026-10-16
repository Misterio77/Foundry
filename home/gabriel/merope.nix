{pkgs, ...}: {
  imports = [
    ./global
    ./features/ai
  ];
  # Blue (240°)
  wallpaper = pkgs.wallpapers.aenami-bright-planet;
}
