{
  pkgs,
  ...
}: {
  home.packages = [pkgs.lichii];

  home.persistence = {
    "/persist".directories = [
      ".config/eden"
      ".local/share/eden"
    ];
  };
}
