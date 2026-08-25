{
  inputs,
  pkgs,
}: let
  runescapePkgs = import inputs.nixpkgs-runescape {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.permittedInsecurePackages = ["openssl-1.1.1w"];
  };
in rec {
  # Packages with an actual source
  lyrics = pkgs.python3Packages.callPackage ./lyrics {};
  prefetcharr = pkgs.callPackage ./prefetcharr {};
  alt1 = pkgs.callPackage ./alt1 {};
  materia-theme = pkgs.callPackage ./materia-theme {};
  hyprbars = pkgs.callPackage ./hyprbars {};
  jellysearch = pkgs.callPackage ./jellysearch {};
  golive = pkgs.callPackage ./golive {};
  website = pkgs.callPackage ../projects/website {};
  runelite-query = pkgs.callPackage ../projects/runelite-query {};
  gtkhal = pkgs.callPackage ../projects/gtkhal {};
  runescape = pkgs.callPackage ./runescape {
    inherit (runescapePkgs) openssl_1_1;
  };

  # Personal scripts
  pass-wofi = pkgs.callPackage ./pass-wofi {};
  xpo = pkgs.callPackage ./xpo {};
  clip-notify = pkgs.callPackage ./clip-notify {};
  jagex-auth = pkgs.callPackage ./jagex-auth {};
  llm-suggest-lsp = pkgs.callPackage ./llm-suggest-lsp {};
  overleaf-sync = pkgs.callPackage ./overleaf-sync {};

  # My slightly customized plymouth theme, just makes the blue outline white
  plymouth-spinner-monochrome = pkgs.callPackage ./plymouth-spinner-monochrome {};

  # Wallpapers
  # Expose as a single package, that also has passthru attributes for the individual ones
  wallpapers = let
    collection = import ./wallpapers {inherit pkgs;};
    combined = pkgs.linkFarmFromDrvs "wallpapers" (pkgs.lib.attrValues collection);
  in
    combined // collection;
}
