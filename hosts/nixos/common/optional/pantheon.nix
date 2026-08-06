{
  services = {
    xserver = {
      enable = true;
      desktopManager.pantheon = {
        enable = true;
      };
      displayManager.lightdm = {
        enable = true;
        greeters.pantheon.enable = true;
      };
    };
    pantheon = {
      apps.enable = true;
    };
  };
  # Fix shutdown taking a long time
  # https://gist.github.com/worldofpeace/27fcdcb111ddf58ba1227bf63501a5fe
  systemd.extraConfig = ''
    DefaultTimeoutStopSec=10s
    DefaultTimeoutStartSec=10s
  '';

  services.avahi.enable = false;
  networking.networkmanager.enable = false;
}
