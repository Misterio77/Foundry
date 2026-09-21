{
  pkgs,
  config,
  lib,
  ...
}: let
  gpgAgentProxy = pkgs.writeShellApplication {
    name = "gpg-agent-proxy";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.python3
    ];
    text = ''
      exec python3 ${./gpg-agent-proxy.py} "$@"
    '';
  };

  proxySocketDir = "%t/gnupg";
  agentSocket = "${proxySocketDir}/S.gpg-agent";
  agentSocketReal = "${agentSocket}.real";
  agentExtraSocket = "${proxySocketDir}/S.gpg-agent.extra";
  agentExtraSocketReal = "${agentExtraSocket}.real";
  agentSshSocket = "${proxySocketDir}/S.gpg-agent.ssh";
  agentSshSocketReal = "${agentSshSocket}.real";
in {
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    sshKeys = ["149F16412997785363112F3DBD713BC91D51B831"];
    enableExtraSocket = true;
    extraConfig = ''
      verbose
      debug ipc
    '';
    pinentry.package =
      if config.gtk.enable
      then pkgs.pinentry-gnome3
      else pkgs.pinentry-tty;
  };

  home.packages = [gpgAgentProxy] ++ lib.optional config.gtk.enable pkgs.gcr_3;

  systemd.user.sockets = {
    gpg-agent.Socket.ListenStream = lib.mkForce agentSocketReal;
    gpg-agent-ssh.Socket.ListenStream = lib.mkForce agentSshSocketReal;
    gpg-agent-extra.Socket.ListenStream = lib.mkForce agentExtraSocketReal;
  };

  systemd.user.services = lib.mkIf config.gtk.enable {
    gpg-agent-proxy = {
      Unit = {
        Description = "GPG agent notification proxy";
        Requires = ["gpg-agent.socket"];
        After = ["gpg-agent.socket"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe gpgAgentProxy} --listen ${agentSocket} --upstream ${agentSocketReal} --mode assuan";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["default.target"];
    };

    gpg-agent-extra-proxy = {
      Unit = {
        Description = "GPG extra agent notification proxy";
        Requires = ["gpg-agent-extra.socket"];
        After = ["gpg-agent-extra.socket"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe gpgAgentProxy} --listen ${agentExtraSocket} --upstream ${agentExtraSocketReal} --mode assuan";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["default.target"];
    };

    gpg-agent-ssh-proxy = {
      Unit = {
        Description = "GPG SSH agent notification proxy";
        Requires = ["gpg-agent-ssh.socket"];
        After = ["gpg-agent-ssh.socket"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe gpgAgentProxy} --listen ${agentSshSocket} --upstream ${agentSshSocketReal} --mode ssh";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["default.target"];
    };
  };

  programs = let
    fixGpg =
      /*
      bash
      */
      ''
        systemctl --user start gpg-agent-proxy.service gpg-agent-ssh-proxy.service gpg-agent.socket gpg-agent-ssh.socket 2>/dev/null || true
      '';
  in {
    # Start gpg-agent if it's not running or tunneled in
    # SSH does not start it automatically, so this is needed to avoid having to use a gpg command at startup
    # https://www.gnupg.org/faq/whats-new-in-2.1.html#autostart
    bash.profileExtra = fixGpg;
    fish.loginShellInit = fixGpg;
    zsh.loginExtra = fixGpg;
    nushell.extraLogin = fixGpg;

    gpg = {
      enable = true;
      settings = {
        trust-model = "tofu+pgp";
      };
      publicKeys = [
        {
          source = ../../pgp.asc;
          trust = 5;
        }
      ];
    };
  };
}
