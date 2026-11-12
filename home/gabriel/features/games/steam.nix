{
  pkgs,
  inputs,
  ...
}: {
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
        dllOverrides.d3dcompiler_43 = "n,b";
        files.game.place."d3dcompiler_43.dll".source = "${pkgs.sekiro-fps-unlock-and-more-native}/d3dcompiler_43.dll";
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
