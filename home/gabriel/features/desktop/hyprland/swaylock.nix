{
  config,
  pkgs,
  ...
}: let
  inherit (config.colorscheme) colors;
in {
  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      effect-blur = "20x3";
      fade-in = 0.1;

      font = config.fontProfiles.regular.name;
      font-size = config.fontProfiles.regular.size + 3;

      line-uses-inside = true;
      disable-caps-lock-text = true;
      indicator-caps-lock = true;
      indicator-radius = 40;
      indicator-idle-visible = true;
      indicator-y-position = 1000;

      ring-color = "${colors.surface_bright}";
      inside-wrong-color = "${colors.on_error}";
      ring-wrong-color = "${colors.error}";
      key-hl-color = "${colors.tertiary}";
      bs-hl-color = "${colors.on_tertiary}";
      ring-ver-color = "${colors.secondary}";
      inside-ver-color = "${colors.on_secondary}";
      inside-color = "${colors.surface}";
      text-color = "${colors.on_surface}";
      text-clear-color = "${colors.on_surface_variant}";
      text-ver-color = "${colors.on_secondary}";
      text-wrong-color = "${colors.on_surface_variant}";
      text-caps-lock-color = "${colors.on_surface_variant}";
      inside-clear-color = "${colors.surface}";
      ring-clear-color = "${colors.primary}";
      inside-caps-lock-color = "${colors.on_tertiary}";
      ring-caps-lock-color = "${colors.surface}";
      separator-color = "${colors.surface}";
    };
  };
}
