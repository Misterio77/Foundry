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
    default_view = "default";
    views = {
      default = {
        group_by = ["list"];
        sort_by = ["completed" "priority" "due" "summary"];
      };
      priority = {
        group_by = ["priority"];
        sort_by = ["due" "list" "summary"];
      };
      agenda = {
        group_by = ["due" "list"];
        sort_by = ["priority" "summary"];
      };
    };
    hooks.after_apply = [systemctl "--user" "start" "vdirsyncer.service"];
  };
}
