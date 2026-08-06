# Manual steps:
# 1. bootctl status
# 2. Make sure you have BIOS password and disk encryption
# 3. sbctl create-keys
# 4. Put secure boot into setup mode
# 5. sbctl enroll-keys --microsoft
# 6. Enable secure boot
# 7. systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12+13+14+15:sha256=0000000000000000000000000000000000000000000000000000000000000000 --wipe-slot=tpm2 <DEVICE>
#      Explanation:
#      - PCR7: Secure boot is on
#      - PCR0+2: UEFI integrity
#      - PCR12+13+14: Boot loader integrity
#      - PCR15: No LUKS partition has been opened yet
{pkgs, inputs, lib, ...}: {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  environment.systemPackages = [pkgs.sbctl];
  environment.persistence = {
    "/persist".directories = [{directory = "/var/lib/sbctl";}];
  };
}
