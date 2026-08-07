{
  imports = [
    ./khal.nix
    ./khard.nix
    ./todoman.nix
    ./oama.nix

    ./mail.nix
    ./calendar.nix
    ./neomutt.nix

    # Pass feature is required
    ../pass
  ];
}
