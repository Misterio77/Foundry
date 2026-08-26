{
  pkgs,
  config,
  ...
}: {
  home.packages = [
    (pkgs.jagex-auth.wrapLaunch pkgs.runelite)
    (pkgs.jagex-auth.wrapLaunch pkgs.hdos)
    (pkgs.jagex-auth.wrapLaunch pkgs.runescape)
    pkgs.alt1
    pkgs.jagex-auth
    pkgs.runelite-query
  ];

  home.file.".runelite/sideloaded-plugins".source = "${config.home.path}/share/runelite/plugins";

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
