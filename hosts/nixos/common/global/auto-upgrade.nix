{inputs, config, ...}: {
  system.hydraAutoUpgrade = {
    enable = true;
    dates = "*:0/10"; # Every 10 minutes
    instance = "https://hydra.m7.rs";
    project = "foundry";
    jobset = "main";
    job = "hosts.${config.networking.hostName}";
  };
  # Disable timer if flake is dirty
  systemd.timers.nixos-upgrade.enable = inputs.self ? rev;
}
