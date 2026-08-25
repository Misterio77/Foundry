{
  pkgs,
  config,
  lib,
  ...
}: let
  useHelix = config.programs.helix.enable;
in {
  programs.fish = {
    interactiveShellInit = ''
      ${
        if useHelix
        then "fish_helix_key_bindings"
        else "fish_vi_key_bindings"
      }
      bind tab __fish_at_file_or_complete
      bind --mode insert tab __fish_at_file_or_complete
      set fish_cursor_default     block      blink
      set fish_cursor_insert      line       blink
      set fish_cursor_replace_one underscore blink
      set fish_cursor_visual      block
    '';
    plugins = lib.optional useHelix {
      name = "fish-helix";
      src = pkgs.stdenv.mkDerivation {
        pname = "fish-helix";
        version = "unstable";
        src = pkgs.fetchFromGitHub {
          owner = "sshilovsky";
          repo = "fish-helix";
          rev = "8a5c7999ec67ae6d70de11334aa888734b3af8d7";
          hash = "sha256-04cL9/m5v0/5dkqz0tEqurOY+5sDjCB5mMKvqgpV4vM=";
        };
        patches = [../../../../../overlays/fish-helix-modern-fish-compat.patch];
        dontBuild = true;
        installPhase = "cp -r . $out";
      };
    };
  };
}
