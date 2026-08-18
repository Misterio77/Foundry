{
  outputs,
  lib,
  systemManagerHostName,
  ...
}: let
  # Every host we know a key for, mapped to the file holding it.
  hostKeyFiles =
    lib.genAttrs (lib.attrNames outputs.nixosConfigurations)
    (hostname: ../../../nixos/${hostname}/ssh_host_ed25519_key.pub)
    // lib.genAttrs (lib.attrNames outputs.systemConfigs)
    (hostname: ../../${hostname}/ssh_host_ed25519_key.pub);
in {
  services.openssh = {
    enable = true;
    settings = {
      # Harden
      PasswordAuthentication = false;
      PermitRootLogin = "no";

      # Automatically remove stale sockets
      StreamLocalBindUnlink = "yes";
      # Allow forwarding ports to everywhere
      GatewayPorts = "clientspecified";
      # Let WAYLAND_DISPLAY be forwarded
      AcceptEnv = ["WAYLAND_DISPLAY"];
      X11Forwarding = true;
    };

    # Unlike NixOS, nothing generates these: System Manager's openssh module
    # runs Ubuntu's /usr/sbin/sshd (so it keeps working with Ubuntu's PAM), and
    # openssh-server already created the key at install time. sops reads the
    # same file, see ./sops.nix.
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  programs.ssh = {
    # Takes over /etc/ssh/ssh_config (Ubuntu's is backed up), which is what
    # makes the known hosts below system-wide.
    enable = true;
    # No default on non-NixOS, and X11Forwarding above asserts on it.
    setXAuthLocation = true;

    # Each hosts public key
    knownHosts =
      lib.mapAttrs (hostname: publicKeyFile: {
        inherit publicKeyFile;
        extraHostNames =
          [
            "${hostname}.m7.rs"
          ]
          ++
          # Alias for localhost if it's the same host
          (lib.optional (hostname == systemManagerHostName) "localhost")
          # Alias to m7.rs and git.m7.rs if it's alcyone
          ++ (lib.optionals (hostname == "alcyone") [
            "m7.rs"
            "git.m7.rs"
          ]);
      })
      hostKeyFiles;
  };
}
