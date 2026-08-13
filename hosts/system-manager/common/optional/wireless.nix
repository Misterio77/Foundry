{...}: {
  imports = [../../../common/wireless.nix];

  # The upstream module emits no country line; Ubuntu's netplan-generated
  # config used to set this, and dropping it would silently relax the
  # regulatory limits.
  networking.wireless.extraConfig = "country=BR";

  # Ubuntu ships two supplicants that would fight ours over the interface and
  # over /run/wpa_supplicant (which our unit claims via RuntimeDirectory=):
  # the templated one, and the DBus-activated one. The latter must be masked
  # rather than merely disabled, since any client touching
  # fi.w1.wpa_supplicant1 would otherwise start it again.
  systemd.maskedUnits = [
    "wpa_supplicant.service"
    "wpa_supplicant@.service"
  ];
}
