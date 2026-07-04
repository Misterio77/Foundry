# My wallpaper collection. Each wallpaper is fetched from imgur and carries a
# precomputed `sourceColor` (matugen's extracted seed) in passthru, so the
# colorscheme can be generated purely (no image decoding / IFD at eval time).
# Regenerate seeds with the helper in modules/home-manager/colors.nix notes.
{pkgs}: let
  inherit (pkgs) lib;
  mk = w:
    (pkgs.fetchurl {
      inherit (w) sha256;
      name = "${w.name}.${w.ext}";
      url = "https://i.imgur.com/${w.id}.${w.ext}";
    })
    .overrideAttrs (old: {
      passthru = (old.passthru or {}) // {inherit (w) sourceColor;};
    });
in
  lib.listToAttrs (map (w: {
      inherit (w) name;
      value = mk w;
    }) (lib.importJSON ./list.json))
