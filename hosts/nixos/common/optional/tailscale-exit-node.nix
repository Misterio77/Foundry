{
  imports = [../global/tailscale.nix];
  services.tailscale = {
    useRoutingFeatures = "both";
    extraUpFlags = ["--advertise-exit-node"];
  };
}
