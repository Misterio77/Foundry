{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./runescape
    ./steam.nix
    ./prism-launcher.nix
    ./hytale.nix
  ];
  home = {
    packages = with pkgs; [gamescope];
    persistence = {
      "/persist".directories = [
        ".config/unity3d" # Unity game saves
      ];
    };
  };
}
