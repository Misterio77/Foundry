{lib, ...}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = lib.mkDefault "client";
    extraUpFlags = ["--login-server https://tailscale.m7.rs"];
  };
  networking.firewall.allowedUDPPorts = [41641]; # Facilitate firewall punching

  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/tailscale";
    }];
  };
}
