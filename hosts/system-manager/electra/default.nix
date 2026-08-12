{...}: {
  imports = [
    ../common/global
    ../common/users/gabriel
  ];

  _module.args.systemManagerHostName = "electra";
  nixpkgs.hostPlatform = "x86_64-linux";
}
