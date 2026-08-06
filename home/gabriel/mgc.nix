{pkgs, ...}: {
  imports = [
    ./generic.nix
    ./features/desktop/hyprland
    ./features/desktop/wireless
    ./features/pass
    ./features/ai
  ];

  targets.genericLinux = {
    enable = true;
    # System Manager owns /run/opengl-driver through nix-system-graphics.
    gpu.enable = false;
  };

  monitors = [
    {
      name = "eDP-1";
      width = 1920;
      height = 1080;
      workspace = "1";
      primary = true;
      scale = 1.25;
    }
  ];

  wallpaper = pkgs.wallpapers.deer-lunar-fantasy;

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
