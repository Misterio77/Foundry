{pkgs, ...}: {
  imports = [
    ./global
    ./features/ai
  ];
  # Amber (80°)
  wallpaper = pkgs.wallpapers.autumn-leaves-orange;
}
