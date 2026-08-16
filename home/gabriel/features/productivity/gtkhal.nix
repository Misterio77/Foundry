{
  config,
  pkgs,
  lib,
  ...
}:
lib.mkIf config.gtk.enable {
  home.packages = [pkgs.gtkhal];
}
