{
  config,
  pkgs,
  ...
}: let
  color = config.colorscheme.colors.inverse_primary;
  python = pkgs.python3.withPackages (p: [p.hidapi p.openrazer p.pyudev]);
in {
  systemd.user.services.rgb = {
    Unit.Description = "Apply the theme color to USB peripherals";
    Service = {
      ExecStart = "${python}/bin/python ${./rgb.py} ${color}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = ["default.target"];
  };
}
