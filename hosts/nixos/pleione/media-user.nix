{
  users.users.media = {
    isNormalUser = true;
    # Passwordless login
    hashedPassword = "";
    # Avoid putting it on 'users'
    group = "media";
    home = "/home/media";
  };
  users.groups.media = {};

  environment.persistence = {
    "/persist".directories = [{
      directory = "/home/media";
      user = "media";
      group = "media";
    }];
  };
}
