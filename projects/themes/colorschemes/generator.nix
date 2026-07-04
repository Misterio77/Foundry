{pkgs, ...}: let
  inherit (pkgs) lib;
  generateColorscheme = name: source: let
    schemeTypes = ["content" "expressive" "fidelity" "fruit-salad" "monochrome" "neutral" "rainbow" "tonal-spot"];
    isHexColor = c: lib.isString c && (builtins.match "#([0-9a-fA-F]{3}){1,2}" c) != null;

    config = (pkgs.formats.toml {}).generate "config.toml" {
      templates = {};
      config = {
        custom_colors = {
          red = "#dd0000";
          orange = "#dd5522";
          yellow = "#dddd00";
          green = "#22dd22";
          cyan = "#22dddd";
          blue = "#2222dd";
          magenta = "#dd22dd";
        };
      };
    };
  in
    pkgs.runCommand "colorscheme-${name}" {
      # __contentAddressed = true;
      passthru = let
        drv = generateColorscheme name source;
      in {
        inherit schemeTypes;
        # Incurs IFD
        imported = lib.genAttrs schemeTypes (scheme: lib.importJSON "${drv}/${scheme}.json");
      };
    } ''
      mkdir "$out" -p
      for type in ${lib.concatStringsSep " " schemeTypes}; do
        ${pkgs.matugen}/bin/matugen ${
        if (isHexColor source)
        then "color hex"
        else "image"
      } --config ${config} -j hex -t "scheme-$type" "${source}" > "$out/$type.json"
      done
    '';
in
  generateColorscheme
