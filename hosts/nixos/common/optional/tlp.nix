{lib, ...}: {
  services.tlp.enable = true;
  services.power-profiles-daemon.enable = lib.mkAfter false;
}
