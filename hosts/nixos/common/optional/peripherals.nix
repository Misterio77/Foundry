{
  services.hardware = {
    openrgb = {
      enable = true;
      settings = {
        Detectors.detectors = {
          "ASUS Aura Motherboard" = true;
          "Razer Naga Epic Chroma" = true;
          "Keychron V3" = true;
        };
        QMKOpenRGBDevices.devices = [{
          name = "Keychron V3";
          usb_pid = "0331";
          usb_vid = "3434";
        }];
      };
    };
  };
  hardware = {
    keyboard.qmk.enable = true;
    opentabletdriver.enable = true;
  };
}
