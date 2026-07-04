{
  inputs,
  outputs,
}: let
  inherit (inputs.nixpkgs) lib;

  notBroken = pkg: !(pkg.meta.broken or false);
  isDistributable = pkg: (pkg.meta.license or {redistributable = true;}).redistributable;
  hasPlatform = sys: pkg: lib.elem sys (pkg.meta.platforms or [sys]);
  filterValidPkgs = sys: pkgs:
    lib.filterAttrs (_: pkg:
      lib.isDerivation pkg
      && hasPlatform sys pkg
      && notBroken pkg
      && isDistributable pkg)
    pkgs;
in {
  pkgs = lib.mapAttrs filterValidPkgs outputs.packages;
  hosts = lib.mapAttrs (_: cfg: cfg.config.system.build.toplevel) outputs.nixosConfigurations;
  homes = lib.mapAttrs (_: cfg: cfg.activationPackage) outputs.homeConfigurations;
}
