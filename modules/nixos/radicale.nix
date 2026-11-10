{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.radicale;
  package =
    if cfg.package == null
    then pkgs.radicale
    else cfg.package;
  python = pkgs.python3.withPackages (ps: [
    ps.gunicorn
    (ps.toPythonModule package)
  ]);
  settingsFormat = pkgs.formats.ini {
    listToValue = lib.concatMapStringsSep ", " (lib.generators.mkValueStringDefault {});
  };
  settingsFile =
    if cfg.settings == {}
    then pkgs.writeText "radicale.conf" cfg.config
    else settingsFormat.generate "radicale.conf" cfg.settings;
in {
  options.services.radicale.unixSocket = {
    enable = lib.mkEnableOption "serving Radicale over a permissioned Unix socket using Gunicorn";
    path = lib.mkOption {
      type = lib.types.str;
      default = "/run/radicale-http.sock";
      description = "Path of the systemd-owned HTTP socket.";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = cfg.group;
      defaultText = lib.literalExpression "config.services.radicale.group";
      description = "Group allowed to connect to the socket and supply trusted identity headers.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.unixSocket.enable) {
    systemd.sockets.radicale = {
      wantedBy = ["sockets.target"];
      socketConfig = {
        ListenStream = cfg.unixSocket.path;
        SocketUser = "root";
        SocketGroup = cfg.unixSocket.group;
        SocketMode = "0660";
        RemoveOnStop = true;
      };
    };
    systemd.services.radicale = {
      requires = ["radicale.socket"];
      after = ["radicale.socket"];
      environment.RADICALE_CONFIG = settingsFile;
      serviceConfig = {
        # Inherit the socket without giving the proxy access to Radicale's storage group.
        ExecStart = lib.mkForce "${python}/bin/gunicorn --bind ${lib.escapeShellArg "unix:${cfg.unixSocket.path}"} --workers 1 --threads 8 --timeout 60 --forwarder-headers= --no-control-socket radicale:application";
        Sockets = ["radicale.socket"];
      };
    };
  };
}
