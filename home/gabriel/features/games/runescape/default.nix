{pkgs, ...}: let
  runelite = pkgs.jagex-auth.wrapLaunch pkgs.runelite;
  hdos = pkgs.jagex-auth.wrapLaunch pkgs.hdos;
  runescape = pkgs.jagex-auth.wrapLaunch pkgs.runescape;
in {
  home.packages = [
    runelite
    hdos
    runescape
    pkgs.jagex-auth
  ];

  xdg.mimeApps.defaultApplications."x-scheme-handler/jagex" = "jagex-auth-handler.desktop";

  home.persistence = {
    "/persist".directories = [
      ".runelite"
      ".config/hdos"
      ".local/share/jagex-auth"
      "Jagex"
    ];
  };
}
