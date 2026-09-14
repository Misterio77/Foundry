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
    hooks.after_apply = [systemctl "--user" "start" "--no-block" "vdirsyncer.service"];
  };
}
