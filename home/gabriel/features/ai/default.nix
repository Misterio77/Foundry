{
  lib,
  pkgs,
  osConfig,
  ...
}: let
  tokenFile = osConfig.sops.secrets.kagi_session_token.path or null;
in {
  imports = [
    ./hax
    ./pi
  ];

  home.packages = [
    pkgs.web-search
    pkgs.python3
    pkgs.python3Packages.trafilatura
  ];
  home.sessionVariables = lib.optionalAttrs (tokenFile != null) {
    KAGI_SESSION_TOKEN_FILE = tokenFile;
  };
}
