{
  pkgs,
  config,
  ...
}: {
  home.packages = [
    (pkgs.inputs.jagex-auth.default.wrapLaunch pkgs.runelite)
    (pkgs.inputs.jagex-auth.default.wrapLaunch pkgs.hdos)
    (pkgs.inputs.jagex-auth.default.wrapLaunch pkgs.runescape)
    pkgs.inputs.jagex-auth.default
    pkgs.runelite-query
    # Replaces the Plugin Hub copy of 117 HD; uninstall that to avoid duplicates.
    pkgs.runelite-hd
  ];

  home.file.".runelite/sideloaded-plugins".source = "${config.home.path}/share/runelite/plugins";

  home.persistence = {
    "/persist".directories = [
      ".runelite"
      ".config/hdos"
      ".local/share/jagex-auth"
      "Jagex"
    ];
  };
}
