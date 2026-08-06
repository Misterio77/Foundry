{
  config,
  lib,
  pkgs,
  ...
}: {
  users.users.greeter = {
    extraGroups = ["seat"];
  };
  services = {
    seatd.enable = true;
    greetd = {
      enable = true;
      settings.default_session.command = lib.mkOverride 1499 "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --remember --cmd \\$SHELL";
    };
    displayManager = {
      enable = true;
      # Export user sessions to system
      sessionPackages = lib.flatten (lib.mapAttrsToList (_: v: v.home.exportedSessionPackages) config.home-manager.users);
    };
  };
}
