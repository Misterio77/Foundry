# Small color helpers, previously pulled from nix-colors.
{lib}: let
  hexDigit = c:
    {
      "0" = 0;
      "1" = 1;
      "2" = 2;
      "3" = 3;
      "4" = 4;
      "5" = 5;
      "6" = 6;
      "7" = 7;
      "8" = 8;
      "9" = 9;
      "a" = 10;
      "b" = 11;
      "c" = 12;
      "d" = 13;
      "e" = 14;
      "f" = 15;
    }
    .${lib.toLower c};

  hexPairToDec = pair: (hexDigit (builtins.substring 0 1 pair)) * 16 + hexDigit (builtins.substring 1 1 pair);
in rec {
  # "#rrggbb" (or "rrggbb") -> [ r g b ] as decimals
  hexToRGB = value: let
    hex = lib.removePrefix "#" value;
  in
    map (i: hexPairToDec (builtins.substring i 2 hex)) [0 2 4];

  # hexToRGBString "," "#rrggbb" -> "r,g,b"
  hexToRGBString = sep: value: lib.concatMapStringsSep sep toString (hexToRGB value);
}
