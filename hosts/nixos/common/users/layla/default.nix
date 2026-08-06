{config, ...}: {
  imports = [./packages.nix];

  users.mutableUsers = false;
  users.users.layla = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "audio"
    ];
    hashedPasswordFile = config.sops.secrets.layla-password.path;
  };

  sops.secrets.layla-password = {
    sopsFile = ../../secrets.yaml;
    neededForUsers = true;
  };

  # Persist entire home
  environment.persistence = {
    "/persist".directories = ["/home/layla"];
  };
}
