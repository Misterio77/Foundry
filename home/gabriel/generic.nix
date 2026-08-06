{lib, ...}: {
  imports = [./global];

  # The impermanence Home Manager module is injected by its NixOS module and
  # cannot be imported on generic Linux. Keep feature modules portable while
  # making their persistence declarations inert here.
  options.home.persistence = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    internal = true;
  };
  config.home.persistence = lib.mkForce {};
}
