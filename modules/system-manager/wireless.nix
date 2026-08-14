# Compat shim: lets the upstream NixOS `networking.wireless` (wpa_supplicant)
# module evaluate under system-manager.
#
# system-manager reuses nixpkgs' systemdUtils, environment.etc and userborn, so
# the unit, the generated wpa_supplicant.conf and the wpa_supplicant user all
# come out unchanged. Only a handful of NixOS-only options are missing: four
# are read but never acted on, and the udev rules are re-expressed on top of
# environment.etc, which the host distro reads from the same path.
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.services;
in {
  imports = [
    "${inputs.nixpkgs}/nixos/modules/services/networking/wpa_supplicant.nix"
  ];

  options = {
    # Set by the wpa_supplicant module; the host distro ships its own regdb
    # (Ubuntu: /lib/firmware/regulatory.db).
    hardware.wirelessRegulatoryDatabase = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
    };

    # Only read by the module's assertions.
    networking.networkmanager.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
    };
    services.connman.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = true;
    };

    services.dbus.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Packages whose DBus system policy should be linked into /etc.";
    };
    services.udev.extraRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra udev rules, written to /etc/udev/rules.d.";
    };
  };

  config = lib.mkIf (cfg.udev.extraRules != "") {
    environment.etc."udev/rules.d/99-system-manager.rules".text = cfg.udev.extraRules;
  };
}
