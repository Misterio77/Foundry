{pkgs, ...}: {
  imports = [
    ./global
    ./features/ai
  ];
  # Coral (40°)
  wallpaper = pkgs.wallpapers.mountain-yellow-red;
}
