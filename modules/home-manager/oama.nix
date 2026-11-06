{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.oama;
  settingsFormat = pkgs.formats.json {};
  settingsFile = settingsFormat.generate "oama" cfg.settings;
in {
  options.programs.oama = {
    enable = lib.mkEnableOption "oama";
    settings = lib.mkOption {
      type = settingsFormat.type;
      default = {};
    };
    package = lib.mkOption {
      readOnly = true;
      type = lib.types.package;
      default = pkgs.oama;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];
    xdg.configFile."oama/config.yaml".source = settingsFile;
  };
}
