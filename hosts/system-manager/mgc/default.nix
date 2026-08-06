{...}: {
  imports = [
    ../common/global
    ../common/users/gabriel
  ];

  _module.args.systemManagerHostName = "mgc";
  nixpkgs.hostPlatform = "x86_64-linux";
}
