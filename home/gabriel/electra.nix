{pkgs, ...}: {
  imports = [
    ./generic.nix
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/productivity
    ./features/productivity/accounts/mgc.nix
    ./features/pass
    ./features/ai
  ];

  accounts = {
    email.accounts.mgc.primary = true;
    calendar.accounts.mgc.primary = true;
  };

  targets.genericLinux = {
    enable = true;
    # System Manager owns /run/opengl-driver through nix-system-graphics.
    gpu.enable = false;
  };

  services.kanshi.settings = [
    {
      profile.outputs = [
        {
          criteria = "eDP-1";
          mode = "1920x1080@60Hz";
          scale = 1.25;
        }
      ];
    }
  ];

  # Green (160°)
  wallpaper = pkgs.wallpapers.aenami-northern-lights;

  home.packages = [
    pkgs.wireguard-tools
    pkgs.sshuttle
    pkgs.glab
    pkgs.juju
  ];

  # System Manager and the upstream Nix installer only ship POSIX
  # /etc/profile.d fragments to set up PATH / XDG_DATA_DIRS; fish never sources
  # /etc/profile, and SM's own fish support is an unfinished upstream TODO. So a
  # bare fish shell misses /run/wrappers/bin, /run/system-manager/sw/bin, the
  # nix default profile, and /run/system-manager/sw/share. Translate the two
  # relevant fragments with babelfish and source them. The guard makes it a
  # cheap no-op once the env is present (e.g. a terminal inside the
  # bash-login-wrapped graphical session).
  programs.fish.interactiveShellInit =
    /*
    fish
    */
    ''
      if not contains /run/system-manager/sw/bin $PATH
          for profile_script in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh /etc/profile.d/system-manager-path.sh
              test -r $profile_script; and ${pkgs.babelfish}/bin/babelfish <$profile_script | source
          end
      end
    '';
}
