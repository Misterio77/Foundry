{
  outputs,
  lib,
  config,
  pkgs,
  ...
}: let
  nixosConfigs = builtins.attrNames outputs.nixosConfigurations;
  systemConfigs = builtins.attrNames outputs.systemConfigs;
  homeConfigs = map (n: lib.last (lib.splitString "@" n)) (builtins.attrNames outputs.homeConfigurations);
  hostnames = lib.unique (homeConfigs ++ nixosConfigs ++ systemConfigs);
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      net = {
        header = "Host ${lib.concatStringsSep " " (lib.flatten (map (host: [
            host
            "${host}.m7.rs"
            "${host}.ts.m7.rs"
          ])
          hostnames))}";
        ForwardAgent = true;
        RemoteForward = [
          {
            bind.address = ''/%d/.gnupg-sockets/S.gpg-agent'';
            host.address = ''/%d/.gnupg-sockets/S.gpg-agent.extra'';
          }
          {
            bind.address = ''/%d/.waypipe/server.sock'';
            host.address = ''/%d/.waypipe/client.sock'';
          }
        ];
        ForwardX11 = true;
        ForwardX11Trusted = true;
        SetEnv.WAYLAND_DISPLAY = "wayland-waypipe";
        StreamLocalBindUnlink = "yes";
        # Keep connections to the fleet warm after first use: speeds up
        # subsequent ssh, and lets the tmux picker enumerate a box's sessions
        # over the existing master (ssh -O check) without dialing out.
        ControlMaster = "auto";
        ControlPersist = "1m";
      };
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
    };
  };

  systemd.user.services = {
    waypipe-server = {
      Unit.Description = "Runs waypipe server on startup to support SSH forwarding";
      Service = {
        Type = "simple";
        ExecStartPre = "${lib.getExe' pkgs.coreutils "mkdir"} %h/.waypipe -p";
        ExecStart = "${lib.getExe (config.lib.nixGL.wrap pkgs.waypipe)} --socket %h/.waypipe/server.sock --title-prefix '[%H] ' --login-shell --display wayland-waypipe server -- ${lib.getExe' pkgs.coreutils "sleep"} infinity";
        ExecStopPost = "${lib.getExe' pkgs.coreutils "rm"} -f %h/.waypipe/server.sock %t/wayland-waypipe";
      };
      Install.WantedBy = ["default.target"];
    };
    # Link /run/user/$UID/gnupg to ~/.gnupg-sockets
    # So that SSH config does not have to know the UID
    link-gnupg-sockets = {
      Unit = {
        Description = "link gnupg sockets from /run to /home";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/ln -Tfs /run/user/%U/gnupg %h/.gnupg-sockets";
        ExecStop = "${pkgs.coreutils}/bin/rm $HOME/.gnupg-sockets";
        RemainAfterExit = true;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
