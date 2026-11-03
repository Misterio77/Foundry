{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.wofi = {
    enable = true;
    package = pkgs.wofi.overrideAttrs (oa: {
      patches =
        (oa.patches or [])
        ++ [
          ./wofi-run-shell.patch # Fix for https://todo.sr.ht/~scoopta/wofi/174
        ];
    });
    settings = {
      image_size = 48;
      columns = 3;
      allow_images = true;
      insensitive = true;
      run-always_parse_args = true;
      run-cache_file = "/dev/null";
      run-exec_search = true;
      matching = "multi-contains";
    };
  };

  home.packages = let
    inherit (config.programs.password-store) package enable;
  in
    lib.optional enable (pkgs.pass-wofi.override {pass = package;})
    ++ lib.optional config.programs.tmux.enable (pkgs.tmux-picker.override {
      tmux = config.programs.tmux.package;
      wofi = config.programs.wofi.package;
    });
}
