{
  config,
  pkgs,
  ...
}: let
  inherit (config.colorscheme) colors mode;
  yaml = pkgs.formats.yaml {};
in {
  home.packages = [pkgs.jellyfin-tui];

  xdg.configFile."jellyfin-tui/config.yaml" = {
    force = true;
    source = yaml.generate "jellyfin-tui.yaml" {
      servers = [
        {
          name = "Merope";
          url = "https://media.m7.rs";
          quick_connect = true;
          default = true;
        }
      ];

      # Preserve the colorscheme rather than deriving accents from album art.
      auto_color = false;

      themes = [
        {
          name = "Colorscheme";
          base =
            if mode == "dark"
            then "Dark"
            else "Light";

          background = colors.background;
          foreground = colors.on_surface;
          foreground_secondary = colors.on_surface_variant;
          foreground_dim = colors.outline;
          foreground_disabled = colors.outline_variant;
          section_title = colors.primary;

          accent = colors.primary;
          border = colors.outline_variant;
          border_focused = colors.primary;

          selected_active_background = colors.primary;
          selected_active_foreground = colors.on_primary;
          selected_inactive_background = colors.surface_container_high;
          selected_inactive_foreground = colors.on_surface_variant;

          scrollbar_thumb = colors.outline;
          scrollbar_track = colors.surface_container_highest;
          progress_fill = colors.primary;
          progress_track = colors.primary_container;
          tab_active_foreground = colors.primary;
          tab_inactive_foreground = colors.outline;

          album_header_background = colors.surface_container;
          album_header_foreground = colors.on_surface;
        }
      ];
    };
  };
}
