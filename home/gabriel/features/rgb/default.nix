{config, lib, pkgs, ...}: let
  color = config.colorscheme.colors.inverse_primary;
in {
  systemd.user.services.rgb = {
  };
}
