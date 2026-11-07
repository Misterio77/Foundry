{...}: {
  programs.oama = {
    enable = true;
    settings = {
      encryption = {
        tag = "GPG";
        contents = "hi@m7.rs";
      };
      services.google = {
        client_id = "348149306378-visjt95me2d6htgl9c5guih3rinjqrrk.apps.googleusercontent.com";
        auth_scope = "https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/contacts";
        access_type = "offline";
      };
    };
  };
}
