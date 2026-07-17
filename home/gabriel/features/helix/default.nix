{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config) colorscheme;
  hash = builtins.hashString "md5" (builtins.toJSON colorscheme.colors);
in {
  home.sessionVariables.EDITOR = "hx";
  home.sessionVariables.COLORTERM = "truecolor";

  programs.helix = {
    enable = true;
    package = pkgs.helix;
    settings = {
      theme = "nix-${hash}";
      editor = {
        soft-wrap.enable = true;
        color-modes = true;
        line-number = "relative";
        bufferline = "multiple";
        indent-guides.render = true;
        file-picker.hidden = false;
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
      };
    };
    languages = {
      language = [
        {
          name = "nix";
          language-servers = ["nixd" "nil"];
          formatter.command = "alejandra";
        }
      ];
      global-language-servers = ["llm-suggest" "colors"];
      language-server = {
        tinymist.config = {
          typstExtraArgs = ["main.typ"];
          exportPdf = "onType";
          outputPath = "$root/$name";
        };

        scls.command = lib.getExe pkgs.simple-completion-language-server;
        colors.command = lib.getExe pkgs.uwu-colors;
        llm-suggest.command = lib.getExe pkgs.llm-suggest-lsp;
      };
    };
    themes."nix-${hash}" = import ./theme.nix {inherit colorscheme;};
  };
  xdg.configFile."helix/config.toml".onChange = ''
    ${pkgs.procps}/bin/pkill -u $USER -USR1 hx || true
  '';
}
