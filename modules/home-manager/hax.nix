{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hax;
  settingsFormat = pkgs.formats.json {};
in {
  options.programs.hax = {
    enable = lib.mkEnableOption "hax coding agent";

    package = lib.mkPackageOption pkgs "hax" {};

    context = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = "Global instructions exposed to hax as AGENTS.md.";
    };

    skills = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = "Directory of agent skills exposed to hax.";
    };

    settings = lib.mkOption {
      type = settingsFormat.type;
      default = {};
      description = "Settings written to hax's config.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];

    xdg.configFile =
      lib.optionalAttrs (cfg.context != null) {
        "hax/AGENTS.md".source = cfg.context;
      }
      // lib.optionalAttrs (cfg.skills != null) {
        "hax/skills".source = cfg.skills;
      }
      // lib.optionalAttrs (cfg.settings != {}) {
        "hax/config.json".source = settingsFormat.generate "hax-config.json" cfg.settings;
      };
  };
}
