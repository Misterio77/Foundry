{
  config,
  inputs,
  lib,
  outputs,
  pkgs,
  ...
}: let
  allowedSigners = pkgs.writeText "ci-allowed-signers" ''
    * namespaces="git" ${lib.trim (builtins.readFile ../../../../home/gabriel/ssh.pub)}
  '';
in {
  imports = [inputs.nixbot.nixosModules.nixbot];

  services.nixbot = {
    enable = true;
    domain = "ci.m7.rs";
    nginx.enableACME = true;
    buildSystems = ["aarch64-linux" "x86_64-linux"];
    evalWorkerCount = 2;
    evalMaxMemorySize = 4096;
    buildConcurrency = 12;
    # Native ARM rebuilds can exceed the upstream three-hour default.
    buildTimeout = 12 * 60 * 60;
    buildMaxSilentTime = 60 * 60;
    pullBased.repositories."m7/Foundry" = {
      url = "git://m7.rs/Foundry";
      defaultBranch = "main";
      pollInterval = 60;
    };
    postBuildSteps = [
      {
        name = "verify-commit-signature";
        warnOnly = false;
        command = [
          "${pkgs.git}/bin/git"
          "-c"
          "gpg.format=ssh"
          "-c"
          "gpg.ssh.program=${pkgs.openssh}/bin/ssh-keygen"
          "-c"
          "gpg.ssh.allowedSignersFile=${allowedSigners}"
          "verify-commit"
          "--"
          (inputs.nixbot.lib.interpolate "%(prop:revision)s")
        ];
      }
    ];
    # This instance trusts tailnet members to restart/cancel builds.
    allowUnauthenticatedControl = true;
  };

  services.nginx.virtualHosts."ci.m7.rs".extraConfig = ''
    allow 127.0.0.1;
    allow ::1;
    allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v4};
    allow ${outputs.nixosConfigurations.alcyone.config.services.headscale.settings.prefixes.v6};
    deny all;
  '';

  nix = {
    distributedBuilds = true;
    settings = {
      max-jobs = 4;
      builders-use-substitutes = true;
    };
    buildMachines = [
      {
        hostName = "taygeta";
        sshUser = "nix-ssh";
        sshKey = config.sops.secrets.nix-ssh-key.path;
        protocol = "ssh";
        systems = ["x86_64-linux" "i686-linux"];
        maxJobs = 8;
        supportedFeatures = ["kvm" "big-parallel" "nixos-test"];
      }
    ];
  };

  # The daemon, not nixbot, opens the builder SSH connection.
  sops.secrets.nix-ssh-key = {
    sopsFile = ../secrets.yaml;
    owner = "root";
    mode = "0400";
  };

  systemd.services.nixbot = {
    wants = ["tailscale-online.target"];
    after = ["tailscale-online.target"];
  };
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/nixbot";
      user = "nixbot";
      group = "nixbot";
      mode = "0700";
    }
  ];
}
