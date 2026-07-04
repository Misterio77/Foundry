{lib, ...}: let
  inherit (lib) types mkOption;
in {
  options.wallpaper = mkOption {
    # A package (image derivation), so its `sourceColor` passthru survives for
    # the colorscheme. Coerces to its path in string context (e.g. hyprpaper).
    type = types.nullOr types.package;
    default = null;
    description = ''
      Wallpaper image (a package, typically `pkgs.wallpapers.<name>`).
    '';
  };
}
