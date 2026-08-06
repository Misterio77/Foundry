# Graphical greeter, hooks into greetd
{pkgs, ...}: {
  programs.regreet = {
    enable = true;
    cageArgs = ["-d" "-s" "-m" "last"];
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    theme = {
      name = "Materia-dark";
      package = pkgs.materia-theme;
    };
    font = {
      name = "Fira Sans";
      package = pkgs.fira;
      size = 12;
    };
    cursorTheme = {
      package = pkgs.apple-cursor;
      name = "macOS";
    };
  };

  environment.persistence = {
    # Persist last user and last selected session
    "/persist".directories = [{
      directory = "/var/lib/regreet";
      user = "greeter";
      group = "greeter";
    }];
  };
}
