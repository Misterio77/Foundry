{...}: {
  imports = [../../../common/wireless.nix];

  hardware.bluetooth = {
    enable = true;
  };
}
