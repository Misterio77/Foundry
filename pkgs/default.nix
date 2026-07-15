{pkgs ? import <nixpkgs> {}, ...}: rec {
  # Packages with an actual source
  lyrics = pkgs.python3Packages.callPackage ./lyrics {};
  prefetcharr = pkgs.callPackage ./prefetcharr {};
  alt1 = pkgs.callPackage ./alt1 {};
  hyprbars = pkgs.callPackage ./hyprbars {};
  jellysearch = pkgs.callPackage ./jellysearch {};
  runescape = pkgs.callPackage ./runescape {};

  # Personal scripts
  pass-wofi = pkgs.callPackage ./pass-wofi {};
  xpo = pkgs.callPackage ./xpo {};
  clip-notify = pkgs.callPackage ./clip-notify {};
  jagex-auth = pkgs.callPackage ./jagex-auth {};
  llm-suggest-lsp = pkgs.callPackage ./llm-suggest-lsp {};

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
