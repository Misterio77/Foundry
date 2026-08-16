{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.colorscheme) colors;
in {
  home.persistence = {
    "/persist".directories = [
      ".config/qutebrowser/bookmarks"
      ".config/qutebrowser/greasemonkey"
      ".local/share/qutebrowser"
    ];
  };

  xdg.mimeApps.defaultApplications = {
    "application/xhtml+xml" = ["org.qutebrowser.qutebrowser.desktop"];
    "text/html" = ["org.qutebrowser.qutebrowser.desktop"];
    "text/xml" = ["org.qutebrowser.qutebrowser.desktop"];
    "x-scheme-handler/http" = ["org.qutebrowser.qutebrowser.desktop"];
    "x-scheme-handler/https" = ["org.qutebrowser.qutebrowser.desktop"];
    "x-scheme-handler/qute" = ["org.qutebrowser.qutebrowser.desktop"];
  };

  programs.qutebrowser = {
    enable = true;
    loadAutoconfig = true;
    searchEngines = rec {
      kagi = "https://kagi.com/search?q={}";
      duckduckgo = "https://duckduckgo.com/?q={}";
      google = "https://google.com/search?hl=en&q={}";
      k = kagi;
      ddg = duckduckgo;
      g = google;
      DEFAULT = kagi;
    };
    settings = {
      # Workaround for google meet
      qt.args = ["disable-features=PermissionElement"];
      url = rec {
        default_page = "https://kagi.com";
        start_pages = [default_page];
      };
      downloads.open_dispatcher = "${lib.getExe pkgs.handlr-regex} open {}";
      editor.command = ["${lib.getExe pkgs.handlr-regex}" "open" "{file}"];
      tabs = {
        show = "multiple";
        position = "left";
        indicator.width = 0;
      };
      # Also avoids qutebrowser stealing focus when reloading
      new_instance_open_target = "window";
      fonts = {
        default_family = config.fontProfiles.regular.name;
        default_size = "${toString config.fontProfiles.regular.size}pt";
      };
      colors = {
        webpage.preferred_color_scheme = "auto";
        completion = {
          fg = colors.on_surface;
          match.fg = colors.primary;
          even.bg = colors.surface_dim;
          odd.bg = colors.surface_bright;
          scrollbar = {
            bg = colors.surface;
            fg = colors.on_surface;
          };
          category = {
            bg = colors.secondary;
            fg = colors.on_secondary;
            border = {
              bottom = colors.surface;
              top = colors.surface;
            };
          };
          item.selected = {
            bg = colors.primary;
            fg = colors.on_primary;
            match.fg = colors.tertiary;
            border = {
              bottom = colors.outline;
              top = colors.outline;
            };
          };
        };
        contextmenu = {
          disabled = {
            bg = colors.surface_dim;
            fg = colors.on_surface_variant;
          };
          menu = {
            bg = colors.surface;
            fg = colors.on_surface;
          };
          selected = {
            bg = colors.secondary;
            fg = colors.on_secondary;
          };
        };
        downloads = {
          bar.bg = colors.surface_dim;
          error = {
            fg = colors.on_error;
            bg = colors.error;
          };
          start = {
            bg = colors.primary;
            fg = colors.on_primary;
          };
          stop = {
            bg = colors.secondary;
            fg = colors.on_secondary;
          };
        };
        hints = {
          bg = colors.secondary;
          fg = colors.on_secondary;
          match.fg = colors.on_surface;
        };
        keyhint = {
          bg = colors.surface;
          fg = colors.on_surface;
          suffix.fg = colors.on_surface;
        };
        messages = {
          error = {
            bg = colors.error;
            border = colors.outline;
            fg = colors.on_error;
          };
          info = {
            bg = colors.secondary;
            border = colors.outline;
            fg = colors.on_secondary;
          };
          warning = {
            bg = colors.primary;
            border = colors.outline;
            fg = colors.on_primary;
          };
        };
        prompts = {
          bg = colors.surface;
          fg = colors.on_surface;
          border = colors.surface;
          selected.bg = colors.inverse_primary;
        };
        statusbar = {
          caret = {
            bg = colors.surface;
            fg = colors.on_surface;
            selection = {
              bg = colors.surface;
              fg = colors.on_surface_variant;
            };
          };
          command = {
            bg = colors.surface_bright;
            fg = colors.on_surface;
            private = {
              bg = colors.surface_bright;
              fg = colors.on_surface;
            };
          };
          insert = {
            bg = colors.surface;
            fg = colors.primary;
          };
          normal = {
            bg = colors.surface;
            fg = colors.on_surface;
          };
          passthrough = {
            bg = colors.secondary;
            fg = colors.on_secondary;
          };
          private = {
            bg = colors.tertiary;
            fg = colors.on_tertiary;
          };
          progress.bg = colors.tertiary;
          url = {
            error.fg = colors.error;
            fg = colors.on_surface;
            success = {
              http.fg = colors.secondary;
              https.fg = colors.secondary;
            };
            warn.fg = colors.tertiary;
          };
        };
        tabs = {
          bar.bg = colors.surface;
          even = {
            bg = colors.surface_bright;
            fg = colors.on_surface;
          };
          odd = {
            bg = colors.surface_dim;
            fg = colors.on_surface;
          };
          selected = {
            even = {
              bg = colors.primary;
              fg = colors.on_primary;
            };
            odd = {
              bg = colors.primary;
              fg = colors.on_primary;
            };
          };
          pinned = {
            even = {
              bg = colors.surface_bright;
              fg = colors.tertiary;
            };
            odd = {
              bg = colors.surface_dim;
              fg = colors.tertiary;
            };
            selected = {
              even = {
                bg = colors.tertiary;
                fg = colors.on_tertiary;
              };
              odd = {
                bg = colors.tertiary;
                fg = colors.on_tertiary;
              };
            };
          };
        };
      };
    };
    extraConfig = ''
      c.tabs.padding = {"bottom": 10, "left": 10, "right": 10, "top": 10}
      # Let Jagex hand authentication back to the rshub URL handler.
      config.set("content.unknown_url_scheme_policy", "allow-all", "https://account.jagex.com/*/launcher/successful-login*")
    '';
  };
}
