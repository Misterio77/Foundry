{
  config,
  pkgs,
  ...
}: let
  postReceiveHook = pkgs.writeShellApplication {
    name = "post-receive";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      for ((i = 0; i < ''${GIT_PUSH_OPTION_COUNT:-0}; i++)); do
        optionName="GIT_PUSH_OPTION_$i"
        if [[ ''${!optionName-} == "nopush" ]]; then
          echo "Skipping mirrors"
          exit 0
        fi
      done

      mapfile -t remotes < <(git config --get-all mirror.pushRemote)

      if (( ''${#remotes[@]} == 0 )); then
        exit 0
      fi

      if [[ ! -S ''${SSH_AUTH_SOCK:-} ]]; then
        echo >&2 "Cannot mirror: no forwarded SSH agent"
        exit 1
      fi

      status=0
      for remote in "''${remotes[@]}"; do
        echo "Mirroring to $remote"
        GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
          git push --prune "$remote" \
          '+refs/heads/*:refs/heads/*' \
          '+refs/tags/*:refs/tags/*' || status=1
      done

      exit "$status"
    '';
  };
  # Refresh info/refs and objects/info/packs, so repos are fetchable and
  # browsable over dumb HTTP
  postUpdateHook = pkgs.writeShellApplication {
    name = "post-update";
    runtimeInputs = [pkgs.git];
    text = ''
      exec git update-server-info
    '';
  };
  gitHooks = pkgs.linkFarm "git-server-hooks" [
    {
      name = "post-receive";
      path = "${postReceiveHook}/bin/post-receive";
    }
    {
      name = "post-update";
      path = "${postUpdateHook}/bin/post-update";
    }
  ];
  gitConfig = pkgs.writeText "gitconfig" ''
    [core]
      hooksPath = ${gitHooks}
    [receive]
      advertisePushOptions = true
  '';
in {
  services.gitDaemon = {
    enable = true;
    basePath = "/srv/git";
  };
  networking.firewall.allowedTCPPorts = [9418];

  # Dumb HTTP protocol: just plain static files, so things like browsegit work.
  # Only repos marked with git-daemon-export-ok are served, same as gitDaemon.
  services.nginx.virtualHosts."git.m7.rs" = {
    forceSSL = true;
    enableACME = true;
    root = "/srv/git";
    locations."~ ^/(?<repo>[^/]+\\.git)(?<repoPath>/.*)$".extraConfig = ''
      if (!-f /srv/git/$repo/git-daemon-export-ok) {
        return 404;
      }
      add_header Access-Control-Allow-Origin "*" always;
      try_files /$repo$repoPath =404;
    '';
  };

  users = {
    users.git = {
      home = "/srv/git";
      createHome = true;
      homeMode = "755";
      isSystemUser = true;
      shell = "${pkgs.bash}/bin/bash";
      group = "git";
      packages = [pkgs.git];
      openssh.authorizedKeys.keys = config.users.users.gabriel.openssh.authorizedKeys.keys;
    };
    groups.git = {};
  };

  systemd.tmpfiles.settings.srv-git = {
    "/srv/git".d = {
      user = config.users.users.git.name;
      group = config.users.users.git.group;
      mode = "0755";
    };
    "/srv/git/.gitconfig"."L+" = {
      user = config.users.users.git.name;
      group = config.users.users.git.group;
      argument = "${gitConfig}";
    };
  };
}
