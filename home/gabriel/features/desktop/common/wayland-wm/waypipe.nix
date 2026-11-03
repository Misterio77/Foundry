{
  pkgs,
  lib,
  config,
  ...
}: {
  home.packages = [
    pkgs.waypipe
    (pkgs.writeShellScriptBin "remote-launch" ''
      shopt -s nullglob
      for socket in "$HOME"/.ssh/master-gabriel@*; do
        [ -S "$socket" ] || continue
        target="''${socket##*/master-}"
        target="''${target%:*}"
        ${lib.getExe pkgs.openssh} -O check "$target" 2>/dev/null || continue
        exec ${lib.getExe pkgs.openssh} "$target" "$@"
      done
      echo "No active SSH master for remote launch" >&2
      exit 1
    '')
  ];
  systemd.user.services.waypipe-client = {
    Unit.Description = "Runs waypipe client on startup to support SSH forwarding";
    Service = {
      ExecStartPre = "${lib.getExe' pkgs.coreutils "mkdir"} %h/.waypipe -p";
      ExecStart = "${lib.getExe (config.lib.nixGL.wrap pkgs.waypipe)} --socket %h/.waypipe/client.sock client";
      ExecStopPost = "${lib.getExe' pkgs.coreutils "rm"} -f %h/.waypipe/client.sock";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
