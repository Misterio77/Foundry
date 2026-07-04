{
  pkgs,
  wallpapers,
  generateColorscheme,
  ...
}:
pkgs.lib.mapAttrs (_: v: generateColorscheme v.name v) wallpapers
