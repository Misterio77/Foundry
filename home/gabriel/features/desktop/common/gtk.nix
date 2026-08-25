{
  config,
  pkgs,
  lib,
  ...
}: let
  rendersvg = pkgs.runCommand "rendersvg" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.resvg}/bin/resvg $out/bin/rendersvg
  '';

  materiaTheme = name: colors:
    pkgs.materia-theme.overrideAttrs (old: {
      buildInputs =
        old.buildInputs
        ++ [
          pkgs.bc
          rendersvg
        ];
      postPatch = ''
        sed -e 's/handle-horz-.*//' -e 's/handle-vert-.*//' -i ./src/gtk-2.0/assets.txt

        cat > /build/gtk-colors << EOF
          BTN_BG=${colors.primary_container}
          BTN_FG=${colors.on_primary_container}
          BG=${colors.surface}
          FG=${colors.on_surface}
          HDR_BTN_BG=${colors.secondary_container}
          HDR_BTN_FG=${colors.on_secondary_container}
          ACCENT_BG=${colors.primary}
          ACCENT_FG=${colors.on_primary}
          HDR_BG=${colors.surface_bright}
          HDR_FG=${colors.on_surface}
          MATERIA_SURFACE=${colors.surface_bright}
          MATERIA_VIEW=${colors.surface_dim}
          MENU_BG=${colors.surface_container}
          MENU_FG=${colors.on_surface}
          SEL_BG=${colors.primary_fixed_dim}
          SEL_FG=${colors.on_primary}
          TXT_BG=${colors.primary_container}
          TXT_FG=${colors.on_primary_container}
          WM_BORDER_FOCUS=${colors.outline}
          WM_BORDER_UNFOCUS=${colors.outline_variant}
          UNITY_DEFAULT_LAUNCHER_STYLE=False
          NAME=${name}
          MATERIA_STYLE_COMPACT=True
        EOF
        patchShebangs .
        ./change_color.sh -o ${name} /build/gtk-colors -i False -t "$out/share/themes"
      '';
    });
in {
  gtk = {
    enable = true;
    font = {
      inherit (config.fontProfiles.regular) name size;
    };
    gtk4.theme = config.gtk.theme;
    theme = let
      inherit (config.colorscheme) mode colors;
      name = "generated-${builtins.hashString "md5" (builtins.toJSON colors)}-${mode}";
    in {
      inherit name;
      package = materiaTheme name (
        lib.mapAttrs (_: v: lib.removePrefix "#" v) colors
      );
    };
    iconTheme = {
      name = "Papirus-${
        if config.colorscheme.mode == "dark"
        then "Dark"
        else "Light"
      }";
      package = pkgs.papirus-icon-theme;
    };
  };

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    package = pkgs.apple-cursor;
    name = "macOS";
    size = 24;
  };

  services.xsettingsd = {
    enable = true;
    settings = {
      "Net/ThemeName" = "${config.gtk.theme.name}";
      "Net/IconThemeName" = "${config.gtk.iconTheme.name}";
    };
  };

  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
}
