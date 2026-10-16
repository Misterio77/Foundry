{pkgs, ...}: {
  imports = [
    ./global
    ./features/ai
  ];
  # Purple (320°)
  wallpaper = pkgs.wallpapers.nebula-purple-pink;
}
