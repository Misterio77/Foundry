{
  pkgs,
  systemManagerHostName,
  ...
}: {
  environment.systemPackages = [pkgs.fish];

  users = {
    mutableUsers = true;
    groups.gabriel = {};
    users.gabriel = {
      isNormalUser = true;
      group = "gabriel";
      home = "/home/gabriel";
      createHome = false;
      shell = "/run/system-manager/sw/bin/fish";
      extraGroups = [
        "audio"
        "render"
        "sudo"
        "video"
      ];
    };
  };

  sops.secrets = {
    brave_api_key = {
      sopsFile = ../../../../secrets.yaml;
      owner = "gabriel";
    };
    kagi_session_token = {
      sopsFile = ../../../../secrets.yaml;
      owner = "gabriel";
    };
  };

  home-manager.users.gabriel = import ../../../../../home/gabriel/${systemManagerHostName}.nix;
}
