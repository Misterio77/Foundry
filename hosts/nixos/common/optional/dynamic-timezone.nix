{
  services.automatic-timezoned.enable = true;
  systemd.services.automatic-timezoned.serviceConfig.Restart = "always";
}
