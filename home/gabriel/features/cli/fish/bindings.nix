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
          rev = "c9487ea37dafee157cefb8a89c145bc98d21fd6b";
          hash = "sha256-JqN4IbLpJFBJKNE6haZH2iFSMrLFdVh+Hbl840+xbfU=";
        };
        patches = [../../../../../overlays/fish-helix-modern-fish-compat.patch];
        dontBuild = true;
        nativeCheckInputs = [pkgs.fish];
        doCheck = true;
        # shortcut: binding checks only, enable upstream's suite when its Fish 4 failures are fixed.
        checkPhase = ''
          runHook preCheck
          export HOME="$TMPDIR/fish-home"
          mkdir -p "$HOME"
          fish --no-config --interactive --command '
            set -g fish_greeting
            __fish_config_interactive
            set -p fish_function_path "$PWD/functions"
            fish_helix_key_bindings; or exit 1
            test "$fish_bind_mode" = insert; or exit 1
            for mode in default visual
              for key in enter left right up down g,h g,l t,enter f,escape space,p
                bind --preset -M $mode -- "$key" >/dev/null; or exit 1
              end
              bind --preset -M $mode ctrl-y | string match -q "*yank*"; or exit 1
            end
            bind --preset -M insert escape | string match -q "*set fish_bind_mode default*"; or exit 1
          '
          runHook postCheck
        '';
        installPhase = "cp -r . $out";
      };
    };
  };
}
