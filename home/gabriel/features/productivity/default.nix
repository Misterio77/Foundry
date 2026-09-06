{
  imports = [
    ./khal.nix
    ./gtkhal.nix
    ./khard.nix
    ./todomd.nix
    ./oama.nix
    ./aerc.nix

    ./mail.nix
    ./calendar.nix

    # Pass feature is required
    ../pass
  ];
}
