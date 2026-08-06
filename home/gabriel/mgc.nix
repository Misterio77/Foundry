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

  # On NixOS XDG_DATA_DIRS globally includes the nix profiles, so `systemd --user`
  # (and the user D-Bus) discover package-shipped units like the xdg-desktop-portal
  # services under share/systemd/user. Ubuntu's logind starts the user manager
  # without those dirs, so the portals stay invisible. genericLinux only exports
  # XDG_DATA_DIRS to login shells, which is too late for the user manager; feed it
  # through environment.d instead, which systemd reads at manager start. Missing
  # dirs are ignored, so this is safe even before System Manager is active.
  # Takes effect on the next login.
  xdg.configFile."environment.d/10-nix-profile.conf".text = ''
    XDG_DATA_DIRS=$HOME/.nix-profile/share:/run/system-manager/sw/share:/usr/local/share:/usr/share
  '';

  wallpaper = pkgs.wallpapers.deer-lunar-fantasy;
}
