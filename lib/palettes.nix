# TonalPalette + the palette sets for a source color, ported from
# material-colors 0.4.2 (the version matugen 4.0 pins).
# - corePalette: matches matugen's `palettes` JSON output (CorePalette.of).
# - rainbowPalettes: the rainbow *scheme* palettes, consumed by the role layer.
{lib}: let
  h = import ./hct.nix {inherit lib;};
  m = import ./math.nix {inherit lib;};
  inherit (builtins) floor;

  isYellow = hue: hue >= 105.0 && hue < 125.0;
  sanitizeDeg = d: let r = m.fmod d 360.0; in
    if r < 0.0
    then r + 360.0
    else r;
  max = a: b:
    if a > b
    then a
    else b;

  # average two "#rrggbb" per channel (used for the yellow tone-99 quirk)
  averageHex = h1: h2: let
    a = h.hexToRgb h1;
    b = h.hexToRgb h2;
    avg = x: y: floor ((x + y) / 2.0 + 0.5);
  in
    h.rgbToHex {
      r = avg a.r b.r;
      g = avg a.g b.g;
      b = avg a.b b.b;
    };

  tonalPalette = hue: chroma: let
    toneOf = t:
      if t == 99 && isYellow hue
      then averageHex (toneOf 98) (toneOf 100)
      else h.hexFromHct {inherit hue chroma; tone = 1.0 * t;};
  in {
    inherit hue chroma;
    tone = toneOf;
  };
in rec {
  inherit tonalPalette;

  # CorePalette.of(source) — matugen's `palettes` field
  corePalette = {hue, chroma}: {
    primary = tonalPalette hue (max 48.0 chroma);
    secondary = tonalPalette hue 16.0;
    tertiary = tonalPalette (sanitizeDeg (hue + 60.0)) 24.0;
    neutral = tonalPalette hue 4.0;
    neutral_variant = tonalPalette hue 8.0;
    error = tonalPalette 25.0 84.0;
  };

  # SchemeRainbow palettes — consumed by the DynamicColor role layer (brick 4)
  rainbowPalettes = {hue, chroma}: {
    primary = tonalPalette hue 48.0;
    secondary = tonalPalette hue 16.0;
    tertiary = tonalPalette (sanitizeDeg (hue + 60.0)) 24.0;
    neutral = tonalPalette hue 0.0;
    neutral_variant = tonalPalette hue 0.0;
    error = tonalPalette 25.0 84.0;
  };

  # convenience: dump a palette as { "<tone>" = "#hex"; ... } for given tones
  paletteTones = tones: pal: lib.listToAttrs (map (t: lib.nameValuePair (toString t) (pal.tone t)) tones);
}
