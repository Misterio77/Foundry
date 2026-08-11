{pkgs, ...}: let
  runelite = pkgs.jagex-auth.wrapLaunch pkgs.runelite;
  hdos = pkgs.jagex-auth.wrapLaunch pkgs.hdos;
  runescape = pkgs.jagex-auth.wrapLaunch pkgs.runescape;
in {
  home.packages = [
    runelite
    hdos
    runescape
    pkgs.alt1
    pkgs.jagex-auth
  ];

  home.file.".runelite/sideloaded-plugins/runelite-mcp.jar".source = "${pkgs.runelite-mcp}/share/runelite/sideloaded-plugins/runelite-mcp.jar";

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/alt1" = "alt1lite.desktop";
    "x-scheme-handler/rshub" = "jagex-auth-handler.desktop";
  };

  home.persistence = {
    "/persist".directories = [
      ".runelite"
      ".config/alt1"
      ".config/hdos"
      ".local/share/jagex-auth"
      "Jagex"
    ];
  };
}
