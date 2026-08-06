{
  services = {
    xserver = {
      desktopManager.gnome = {
        enable = true;
      };
      displayManager.gdm = {
        enable = true;
        autoSuspend = false;
      };
    };
    gnome.games.enable = true;
  };
  # Fix broken stuff
  services.avahi.enable = false;
  networking.networkmanager.enable = false;
}
