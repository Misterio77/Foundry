{
  config,
  pkgs,
  ...
}: let
  storage = "/srv/media/git-lfs";
  transfer = pkgs.writeShellApplication {
    name = "serve-git-lfs";
    runtimeInputs = [pkgs.coreutils pkgs.util-linux pkgs.git pkgs.git-lfs-transfer];
    text = ''
      pattern='^([a-zA-Z0-9_-][a-zA-Z0-9._-]*\.git) (upload|download)$'
      [[ ''${SSH_ORIGINAL_COMMAND:-} =~ $pattern ]] || exit 1
      repo=''${BASH_REMATCH[1]}
      op=''${BASH_REMATCH[2]}
      cd ${storage}
      mountpoint -q /srv/media || exit 1
      umask 077
      mkdir -p -- "./$repo"
      exec git-lfs-transfer "./$repo" "$op"
    '';
  };
in {
  users.groups.git-lfs = {};
  users.users.git-lfs = {
    isSystemUser = true;
    group = "git-lfs";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = config.users.users.gabriel.openssh.authorizedKeys.keys;
  };
  services.openssh.extraConfig = ''
    Match User git-lfs
      ForceCommand ${transfer}/bin/serve-git-lfs
      DisableForwarding yes
      PermitTTY no
    Match all
  '';
  systemd.tmpfiles.settings.git-lfs.${storage}.d = {
    user = "git-lfs";
    group = "git-lfs";
    mode = "0700";
  };
}
