{...}: {
  # systemd-networkd has no implicit "manage everything" default: a link that
  # matches no .network file stays unmanaged and is never even brought up. On
  # NixOS this file is generated for you (nixos/modules/tasks/
  # network-interfaces-systemd.nix, genericDhcpNetworks); here netplan used to
  # do it. These mirror the upstream match rules, so nothing is named
  # explicitly and new hardware works on plug-in.
  environment.etc = {
    # Type=ether with no kind covers physical ethernet, USB dongles and USB
    # tethered phones alike.
    "systemd/network/99-ethernet-default-dhcp.network".text = ''
      [Match]
      Type=ether
      Kind=!*

      [Network]
      DHCP=yes
      IPv6PrivacyExtensions=kernel
    '';

    # One above ethernet's default of 1024, so wired wins when both are up.
    "systemd/network/99-wireless-client-dhcp.network".text = ''
      [Match]
      WLANInterfaceType=station

      [Network]
      DHCP=yes
      IPv6PrivacyExtensions=kernel

      [DHCPv4]
      RouteMetric=1025

      [IPv6AcceptRA]
      RouteMetric=1025
    '';

    # Neuter netplan without uninstalling it: purging netplan.io would take
    # cloud-init, ubuntu-minimal and ubuntu-server-minimal with it. Masking the
    # generator is reverted by `system-manager deactivate`, unlike apt state.
    #
    # NOTE: systemd.generators would be the natural home for this, but
    # system-manager declares that option without ever wiring it up.
    "systemd/system-generators/netplan".source = "/dev/null";
  };
}
