{
  pkgs,
  lib,
  ...
}: {
  services.avahi.enable = lib.mkForce false;
  services.ipp-usb.enable = true;
  services.printing = {
    enable = true;
    stateless = true;
    drivers = [
      pkgs.epson-escpr2
    ];
  };
  hardware.printers.ensurePrinters = [
    {
      description = "Epson L5590 (USB ESCPR2)";
      name = "Epson_L5590_USB_ESCPR2";
      deviceUri = "usb://EPSON/L5590%20Series?serial=584242573036313348&interface=1";
      model = "epson-inkjet-printer-escpr2/Epson-L5590_Series-epson-escpr2-en.ppd";
      ppdOptions = {
        PageSize = "A4";
        Ink = "COLOR";
        MediaType = "PMPHOTO_HIGH"; # Premium Photo (usually what I use)
        Brightness = "4";
        Contrast = "6";
        Saturation = "15";
      };
    }
  ];
  hardware.sane = {
    enable = true;
    extraBackends = [
      pkgs.sane-airscan
    ];
  };
}
