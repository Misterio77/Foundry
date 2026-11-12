{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  monitor = lib.findFirst (m: m.primary && m.enabled) null config.monitors;
  gamescope = lib.escapeShellArgs (
    [(lib.getExe pkgs.gamescope)]
    ++ lib.optionals (monitor != null) [
      "-W"
      (toString monitor.width)
      "-H"
      (toString monitor.height)
    ]
    ++ ["--"]
  );
  steamHome = "${config.xdg.dataHome}/Steam";
in {
  imports = [inputs.steam-config-nix.homeModules.default];

  home.packages = [
    (pkgs.steam.override {extraPkgs = p: [p.gamescope];})
    pkgs.gamescope
    pkgs.protontricks
  ];

  programs.steam.config = {
    enable = true;
    defaultCompatTool = pkgs.proton-ge-bin;

    apps = {
      "1003590" = {
        name = "Tetris Effect: Connected";
        compatTool = "proton_9";
      };
      "1091500" = {
        name = "Cyberpunk 2077";
        # Cyber Engine Tweaks (version) + RED4ext (winmm): Non-Canon Romances Enhanced,
        # Native Settings UI and ArchiveXL.
        dllOverrides = {
          version = "n,b";
          winmm = "n,b";
        };
        args = ["--launcher-skip" "-skipStartScreen"];
      };
      "1231560" = {
        name = "Aurelia";
        compatTool = "proton_9";
      };
      "1455840" = {
        name = "Dorfromantik";
        compatTool = "proton_10";
      };
      "1493710" = {
        name = "Proton Experimental";
        betaBranch = "bleeding-edge";
      };
      "1569580" = {
        name = "Blue Prince";
        dllOverrides.version = "n,b";
      };
      "1657630" = {
        name = "Slime Rancher 2";
        compatTool = "proton_10";
      };
      "2379780" = {
        name = "Balatro";
        compatTool = "proton_9";
      };
      "291550" = {
        name = "Brawlhalla";
        compatTool = "proton_9";
        env.PROTON_USE_WINED3D = "1";
        wrappers = ["gamemoderun"];
        args = ["-framefix" "-framefixunbounded" "-noeac"];
      };
      "292030" = {
        name = "The Witcher 3";
        args = ["--launcher-skip"];
      };
      "427520" = {
        name = "Factorio";
        betaBranch = "experimental";
      };
      "814380" = {
        name = "Sekiro";
        compatTool = "proton_10";
        allowDownloadsWhileRunning = "always";
        dllOverrides.dinput8 = "n,b";
        # The existing setup runs only the FPS helper under Gamescope, not the game.
        preHook = ''
          ${gamescope} ${lib.escapeShellArg "${steamHome}/steamapps/common/Sekiro/sekirofpsunlock"} 30 ${lib.optionalString (monitor != null) "set-resolution ${toString monitor.width} ${toString monitor.width} ${toString monitor.height}"} &
        '';
      };
      "835960" = {
        name = "The Talos Principle 2";
        compatTool = "proton_10";
        wrappers = ["gamemoderun"];
      };
    };
  };

  home.persistence = {
    "/persist".directories = [
      ".local/share/Steam"
      ".local/share/steam-config-nix"
    ];
  };
}
