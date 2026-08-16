{
  config,
  lib,
  ...
}: {
  # Import calendar files interactively in a terminal
  xdg.desktopEntries.khal-import = {
    name = "Import calendar event";
    exec = "${lib.getExe' config.programs.khal.package "khal"} import %f";
    terminal = true;
    noDisplay = true;
    mimeType = ["text/calendar"];
  };

  # pkgs.khal's desktop entry launches ikhal but declares no MIME types
  xdg.mimeApps.associations.added."x-scheme-handler/calendar" = "khal.desktop";

  programs.khal = {
    enable = true;
    locale = {
      firstweekday = 0;
      weeknumbers = "off";
      unicode_symbols = true;
      dateformat = "%d/%m/%Y";
      timeformat = "%H:%M";
      datetimeformat = "%c";
      longdateformat = "%x";
      longdatetimeformat = "%c";
    };
    settings = {
      default.highlight_event_days = true;
      highlight_days.color = "light blue";
    };
  };
}
