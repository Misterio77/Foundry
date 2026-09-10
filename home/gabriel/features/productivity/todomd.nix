{
  config,
  lib,
  pkgs,
  ...
}: let
  systemctl = lib.getExe' pkgs.systemd "systemctl";
  toml = pkgs.formats.toml {};
in {
  home.packages = [pkgs.todomd];

  xdg.configFile."todomd/config.toml".source = toml.generate "todomd-config.toml" {
    calendar_roots = lib.mapAttrsToList (_: c: c.local.path) config.accounts.calendar.accounts;
    hooks = {
      # Keep vdirsyncer from writing to the vdirs mid-session, push whatever was
      # applied right away, and re-arm the timer however the session ended
      before_session = [systemctl "--user" "stop" "vdirsyncer.timer" "vdirsyncer.service"];
      after_apply = [systemctl "--user" "start" "vdirsyncer.service"];
      after_session = [systemctl "--user" "start" "vdirsyncer.timer"];
    };
  };

  programs.fish.shellAbbrs.todo = "todomd";
}
