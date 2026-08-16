{
  config,
  lib,
  pkgs,
  ...
}: let
  aerc = lib.getExe config.programs.aerc.package;
  c = config.colorscheme.colors;
  reload = command: ''
    socket="''${XDG_RUNTIME_DIR:-/run/user/$UID}/aerc.sock"
    [[ -S "$socket" ]] && ${aerc} '${command}' || true
  '';
in {
  programs.aerc = {
    enable = true;
    extraBinds = {
      global = {
        "$include" = "${config.programs.aerc.package}/share/aerc/binds.conf";
        "<C-c>" = ":quit<Enter>";
        "<C-q>" = ":quit<Enter>";
        "\\[t" = "";
        "\\]t" = "";
        gn = ":next-tab<Enter>";
        gp = ":prev-tab<Enter>";
      };
      messages = {
        D = ":move Trash<Enter>";
        G = "";
        V = "";
        X = ":mark -v<Enter>";
        d = ":move Trash<Enter>";
        g = "";
        ge = ":select -1<Enter>";
        gg = ":select 0<Enter>";
        q = ":quit<Enter>";
        v = "";
        x = ":mark -t<Enter>";
      };
      view = {
        D = ":move Trash<Enter>";
        d = ":move Trash<Enter>";
      };
    };
    extraConfig = {
      general.unsafe-accounts-conf = true;
      compose.address-book-cmd = "khard email --remove-first-line --parsable %s";
      ui = {
        styleset-name = "colorscheme";
        # Nest subfolders (Archive/2025) under their parent, folded by default
        dirlist-tree = true;
        dirlist-collapse = 1;
        tab-title-account = ''{{.Account}}{{with .Unread "Inbox"}} ({{.}}){{end}}'';
      };
      # Home Manager writes the whole aerc.conf, so aerc's shipped filters
      # don't apply and every viewable type has to be listed here. These are
      # all exact types, so the alphabetical order Nix emits is harmless --
      # but the first match wins, so any glob added here needs care.
      filters = {
        "text/plain" = "colorize";
        "text/calendar" = "calendar";
        "message/delivery-status" = "colorize";
        "message/rfc822" = "colorize";
        # '!' hands the terminal to the filter; the html one is already
        # wrapped with w3m by nixpkgs
        "text/html" = "! html -o display_link_number=true -o extbrowser=${lib.getExe' pkgs.xdg-utils "xdg-open"}";
        # Only used when viewer.show-headers is on
        ".headers" = "colorize";
      };
      viewer.pager = "${lib.getExe pkgs.less} -R";
    };

    # Attribute order matters: aerc parses a styleset top to bottom and later
    # statements win. Nix sorts keys alphabetically, which puts the "*"
    # wildcards before the specific objects they're meant to be overridden by.
    stylesets.colorscheme = {
      global = {
        # Start from a blank slate instead of aerc's palette-index defaults
        "*.default" = true;
        "*.normal" = true;
        "*.selected.bg" = c.primary_container;
        "*.selected.fg" = c.on_primary_container;
        "*.selected.bold" = true;

        "default.fg" = c.on_surface;
        "default.bg" = c.surface;

        "error.fg" = c.error;
        "error.bold" = true;
        "warning.fg" = c.yellow;
        "warning.bold" = true;
        "success.fg" = c.green;
        "success.bold" = true;

        "title.fg" = c.on_primary_container;
        "title.bg" = c.primary_container;
        "title.bold" = true;
        "header.fg" = c.primary;
        "header.bold" = true;
        "border.fg" = c.outline_variant;
        "border.bg" = c.surface;
        "spinner.fg" = c.primary;

        "tab.fg" = c.on_surface_variant;
        "tab.bg" = c.surface_container;
        "tab.selected.fg" = c.on_primary_container;
        "tab.selected.bg" = c.primary_container;

        "statusline_*.dim" = false;
        "statusline_default.fg" = c.on_surface_variant;
        "statusline_default.bg" = c.surface_container;
        "statusline_error.fg" = c.error;
        "statusline_error.bold" = true;
        "statusline_success.fg" = c.green;
        "statusline_success.bold" = true;

        "msglist_*.selected.bg" = c.primary_container;
        "msglist_*.selected.fg" = c.on_primary_container;
        "msglist_default.fg" = c.on_surface;
        "msglist_default.bg" = c.surface;
        "msglist_unread.fg" = c.on_surface;
        "msglist_unread.bold" = true;
        "msglist_read.fg" = c.on_surface_variant;
        "msglist_answered.fg" = c.cyan;
        "msglist_forwarded.fg" = c.blue;
        "msglist_flagged.fg" = c.tertiary;
        "msglist_flagged.bold" = true;
        "msglist_deleted.fg" = c.outline;
        "msglist_deleted.dim" = true;
        "msglist_result.fg" = c.yellow;
        "msglist_result.bold" = true;
        "msglist_thread_folded.fg" = c.secondary;
        "msglist_thread_context.fg" = c.outline;
        "msglist_thread_context.dim" = true;
        "msglist_thread_orphan.fg" = c.orange;
        "msglist_marked.fg" = c.on_secondary_container;
        "msglist_marked.bg" = c.secondary_container;
        "msglist_gutter.bg" = c.surface;
        "msglist_pill.fg" = c.on_primary;
        "msglist_pill.bg" = c.primary;

        "dirlist_*.selected.bg" = c.primary_container;
        "dirlist_*.selected.fg" = c.on_primary_container;
        "dirlist_default.fg" = c.on_surface_variant;
        "dirlist_unread.fg" = c.on_surface;
        "dirlist_unread.bold" = true;
        "dirlist_recent.fg" = c.primary;

        "completion_*.bg" = c.surface_container_high;
        "completion_default.fg" = c.on_surface;
        "completion_description.fg" = c.on_surface_variant;
        "completion_description.dim" = true;
        "completion_gutter.bg" = c.surface_container;
        "completion_pill.fg" = c.on_primary;
        "completion_pill.bg" = c.primary;

        "part_switcher.bg" = c.surface_container;
        "part_filename.fg" = c.on_surface;
        "part_mimetype.fg" = c.on_surface_variant;

        "selector_default.fg" = c.on_surface;
        "selector_focused.fg" = c.on_primary_container;
        "selector_focused.bg" = c.primary_container;
        "selector_focused.bold" = true;
        "selector_chooser.fg" = c.primary;
        "selector_chooser.bold" = true;
      };

      viewer = {
        "url.fg" = c.blue;
        "url.underline" = true;
        "header.fg" = c.primary;
        "header.bold" = true;
        "signature.fg" = c.on_surface_variant;
        "signature.dim" = true;
        "diff_meta.fg" = c.on_surface_variant;
        "diff_meta.bold" = true;
        "diff_chunk.fg" = c.cyan;
        "diff_chunk_func.fg" = c.cyan;
        "diff_chunk_func.dim" = true;
        "diff_add.fg" = c.green;
        "diff_del.fg" = c.red;
        "quote_1.fg" = c.cyan;
        "quote_2.fg" = c.blue;
        "quote_3.fg" = c.magenta;
        "quote_4.fg" = c.cyan;
        "quote_4.dim" = true;
        "quote_x.fg" = c.blue;
        "quote_x.dim" = true;
      };
    };
  };

  home.file."${config.xdg.configHome}/aerc/aerc.conf".onChange = reload ":reload -C";
  home.file."${config.xdg.configHome}/aerc/stylesets/colorscheme".onChange =
    reload ":reload -s colorscheme";
}
