{
  # Only over the tailnet: these are wide ranges to leave open on a machine
  # that joins networks it doesn't control.
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };
}
