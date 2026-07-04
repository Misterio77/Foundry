# Pure-Nix Material You colorscheme generator: produces the { colors =
# { dark; light; }; } shape the colorscheme module consumes, assembled from the
# MD3 role layer (lib/scheme.nix) plus harmonized custom colors. This is our own
# implementation of the Material You color science (see lib/{math,hct,palettes,
# scheme}.nix); it replaced the matugen import-from-derivation entirely.
#
# Validated against matugen 2.4.1 (material-colors 0.4.2) for #2B3975: all 49 MD3
# roles are bit-exact in both modes; the 7 custom colors are bit-exact except a
# few channels that land ±1 LSB off, due to Nix series math vs Rust hardware
# transcendentals accumulating through the extra harmonize hue rotation.
{lib}: let
  h = import ./hct.nix {inherit lib;};
  p = import ./palettes.nix {inherit lib;};
  sch = import ./scheme.nix {inherit lib;};
  m = import ./math.nix {inherit lib;};

  sanitize = d: let r = m.fmod d 360.0; in
    if r < 0.0
    then r + 360.0
    else r;
  diffDeg = a: b: 180.0 - m.abs (m.abs (a - b) - 180.0);
  rotDir = a: b:
    if (sanitize (b - a)) <= 180.0
    then 1.0
    else -1.0;

  # Blend.harmonize: shift `custom` hue up to 15 deg toward `source`.
  harmonizeHue = custHex: srcHex: let
    f = h.hctFromHex custHex;
    t = h.hctFromHex srcHex;
    rot = (let d = diffDeg f.hue t.hue; x = d * 0.5; in
      if x < 15.0
      then x
      else 15.0) * (rotDir f.hue t.hue);
  in
    sanitize (f.hue + rot);

  # matugen CustomColorGroup: harmonized-hue tonal palette at chroma 48, with the
  # same tone map as the primary role set (dark 80/20/30/90, light 40/100/90/10).
  customGroup = name: custHex: srcHex: let
    pal = p.tonalPalette (harmonizeHue custHex srcHex) 48.0;
  in {
    dark = {
      "${name}" = pal.tone 80;
      "on_${name}" = pal.tone 20;
      "${name}_container" = pal.tone 30;
      "on_${name}_container" = pal.tone 90;
      "${name}_source" = lib.toLower custHex;
      "${name}_value" = lib.toLower custHex;
    };
    light = {
      "${name}" = pal.tone 40;
      "on_${name}" = pal.tone 100;
      "${name}_container" = pal.tone 90;
      "on_${name}_container" = pal.tone 10;
      "${name}_source" = lib.toLower custHex;
      "${name}_value" = lib.toLower custHex;
    };
  };
in rec {
  inherit harmonizeHue customGroup;

  # source: "#rrggbb" (hex). customColors: { name = "#hex"; ... } (blend/harmonized).
  # Returns { colors = { dark = {..}; light = {..}; }; } matching matugen -j hex.
  generateColorscheme = source: customColors: let
    roleColors = isDark: sch.colorsFor isDark source;
    customFor = isDark: let mode = if isDark then "dark" else "light"; in
      lib.foldlAttrs (acc: name: hex: acc // (customGroup name hex source).${mode}) {} customColors;
    modeColors = isDark:
      (roleColors isDark)
      // (customFor isDark)
      // {source_color = lib.toLower source;};
  in {
    colors = {
      dark = modeColors true;
      light = modeColors false;
    };
  };
}
