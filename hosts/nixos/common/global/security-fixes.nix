{pkgs, ...}: {
  boot.extraModprobeConfig = ''
    install esp4 ${pkgs.coreutils}/bin/false
    install esp6 ${pkgs.coreutils}/bin/false
    install rxrpc ${pkgs.coreutils}/bin/false
    install algif_aead ${pkgs.coreutils}/bin/false
  '';
  boot.blacklistedKernelModules = [
    "esp4"
    "esp6"
    "rxrpc"
    "algif_aead"
  ];
}
