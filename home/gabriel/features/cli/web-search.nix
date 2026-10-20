{
  lib,
  pkgs,
  osConfig,
  ...
}: let
  tokenFile = osConfig.sops.secrets.kagi_session_token.path or null;
in {
  home.packages = [pkgs.web-search];
  home.sessionVariables = lib.optionalAttrs (tokenFile != null) {
    KAGI_SESSION_TOKEN_FILE = tokenFile;
  };
}
