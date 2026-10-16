{pkgs, ...}: {
  imports = [
    ./global
    ./features/ai
  ];
  # Olive (120°)
  wallpaper = pkgs.wallpapers.plains-flowers-green-red;
}
