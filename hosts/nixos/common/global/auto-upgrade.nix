{
  inputs,
  config,
  ...
}: {
  system.nixbotAutoUpgrade = {
    enable = true;
    dates = "*:0/10"; # Every 10 minutes
    instance = "https://ci.m7.rs";
    project = "pull_based/m7/Foundry";
    branch = "main";
    source = "git://m7.rs/Foundry?ref=main";
    job = "ciJobs.hosts.${config.networking.hostName}";
  };
  # Disable timer if flake is dirty
  systemd.timers.nixos-upgrade.enable = inputs.self ? rev;
}
