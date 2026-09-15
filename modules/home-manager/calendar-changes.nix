{lib, ...}: let
  inherit (lib) mkOption types;
  inherit (types) attrsOf submodule nullOr str listOf;
in {
  options = {
    accounts.calendar.accounts = mkOption {
      type = attrsOf (submodule {
        options.vdirsyncer.tokenCommand = mkOption {
          type = nullOr (listOf str);
          default = null;
          example = [
            "oama"
            "access"
            "example@example.com"
          ];
          description = ''
            A command that prints an OAuth access token.
          '';
        };
      });
    };
  };
}
