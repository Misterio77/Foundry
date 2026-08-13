{...}: {
  imports = [../../../wireless.nix];

  hardware.bluetooth = {
    enable = true;
  };
}
