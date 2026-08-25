{pkgs, ...}: let
  steam-with-pkgs = pkgs.steam.override {
    extraPkgs = pkgs:
      with pkgs; [
        libxcursor
        libxi
        libxinerama
        libxscrnsaver
        libpng
        libpulseaudio
        libvorbis
        stdenv.cc.cc.lib
        libkrb5
        keyutils
      ];
  };
in {
  users.users.layla.packages = with pkgs; [
    firefox

    steam-with-pkgs
    gamescope
    protontricks
    lutris
    prismlauncher
  ];
}
