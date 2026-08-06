{
  services.postgresql.enable = true;

  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/postgresql";
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }];
  };
}
