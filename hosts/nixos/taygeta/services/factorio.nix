{config, lib, ...}: let
  stateDir = "/var/lib/${config.services.factorio.stateDirName}";
in {
  services.factorio = {
    enable = true;
    bind = "172.18.0.42";
    loadLatestSave = true;
    openFirewall = true;
    extraSettings = {
      require_user_verification = false;
      non_blocking_saving = true;
    };
    extraSettingsFile = config.sops.templates.factorio-extra-settings.path;
  };
  sops = {
    secrets.factorio-server-password = {
      owner = "factorio";
      sopsFile = ../secrets.yaml;
    };
    templates.factorio-extra-settings.content = builtins.toJSON {
      game_password = config.sops.placeholder.factorio-server-password;
    };
  };

  # Disable DynamicUser
  systemd.services.factorio.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "factorio";
    Group = "factorio";
  };
  users = {
    users.factorio = {
      home = stateDir;
      group = "factorio";
      isSystemUser = true;
    };
    groups.factorio = {};
  };
  environment.persistence = {
    "/persist".directories = [{
      directory = stateDir;
      user = "factorio";
      group = "factorio";
      mode = "0700";
    }];
  };
}
