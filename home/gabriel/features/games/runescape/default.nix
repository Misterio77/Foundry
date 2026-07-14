{
  lib,
  pkgs,
  ...
}: let
  runelite = pkgs.jagex-auth.wrapLaunch pkgs.runelite;
  hdos = pkgs.jagex-auth.wrapLaunch pkgs.hdos;
in {
  home.packages = [
    runelite
    hdos
    pkgs.jagex-auth
  ];

  xdg.desktopEntries.jagex-auth-handler = {
    name = "Jagex Auth URL Handler";
    exec = "${lib.getExe pkgs.jagex-auth} handle-url %u";
    mimeType = ["x-scheme-handler/jagex"];
    noDisplay = true;
  };

  xdg.mimeApps.defaultApplications."x-scheme-handler/jagex" = "jagex-auth-handler.desktop";

  home.persistence = {
    "/persist".directories = [
      ".runelite"
      ".config/hdos"
      ".local/share/jagex-auth"
    ];
  };
}
