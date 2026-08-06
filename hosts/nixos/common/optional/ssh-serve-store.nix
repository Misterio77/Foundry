{
  nix = {
    sshServe = {
      enable = true;
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAz0dIbaTuAihil/si33MQSFH5yBFoupwnV5gcq2CCbO nix-ssh"
      ];
      protocol = "ssh";
      write = true;
    };
    settings.trusted-users = ["nix-ssh"];
  };
}
