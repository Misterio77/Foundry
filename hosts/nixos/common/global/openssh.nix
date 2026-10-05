{
  outputs,
  lib,
  config,
  ...
}: let
  # Every host we know a key for, mapped to the file holding it.
  hostKeyFiles =
    lib.genAttrs (lib.attrNames outputs.nixosConfigurations)
    (hostname: ../../${hostname}/ssh_host_ed25519_key.pub)
    // lib.genAttrs (lib.attrNames outputs.systemConfigs)
    (hostname: ../../../ubuntu/${hostname}/ssh_host_ed25519_key.pub);

  # Sops needs acess to the keys before the persist dirs are even mounted; so
  # just persisting the keys won't work, we must point at /persist
  hasOptinPersistence = config.environment.persistence ? "/persist";
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

    hostKeys = [
      {
        path = "${lib.optionalString hasOptinPersistence "/persist"}/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  programs.ssh = {
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
          (lib.optional (hostname == config.networking.hostName) "localhost")
          # Alias to m7.rs and git.m7.rs if it's alcyone
          ++ (lib.optionals (hostname == "alcyone") [
            "m7.rs"
            "git.m7.rs"
          ]);
      })
      hostKeyFiles;
  };

  # Authenticate sudo through the local or forwarded SSH agent, with password fallback.
  # Only trust root-managed keys; user-writable authorized_keys would bypass sudo auth.
  security.pam.rssh = {
    enable = true;
    settings.auth_key_file = "/etc/ssh/authorized_keys.d/$ruser";
  };
  security.pam.services.sudo.rssh = true;
}
