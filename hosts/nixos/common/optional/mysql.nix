{pkgs, config, ...}: {
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
  };

  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/mysql";
      user = config.services.mysql.user;
      group = config.services.mysql.group;
      mode = "0700";
    }];
  };
}
