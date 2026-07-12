{pkgs, lib, ...}: let
  jellyfin-kiosk = pkgs.writeShellScriptBin "jellyfin-kiosk" ''
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY
    systemctl --user start jellyfin-kiosk-session.target
    ${lib.getExe' pkgs.pulseaudio "pactl"} set-sink-volume @DEFAULT_SINK@ 80%
    QTWEBENGINE_FORCE_USE_GBM=0 ${lib.getExe pkgs.cage} -d -- ${lib.getExe' pkgs.jellyfin-media-player "jellyfin-desktop"} --tv --fullscreen
    systemctl --user stop jellyfin-kiosk-session.target
  '';

  jellyfin-kiosk-session =
    (pkgs.writeTextDir "share/wayland-sessions/jellyfin.desktop" ''
      [Desktop Entry]
      Name=Jellyfin
      Comment=A media platform
      Exec=${lib.getExe jellyfin-kiosk}
      Type=Application
    '').overrideAttrs
      (_: {
        passthru.providedSessions = ["jellyfin"];
      });
in {
  services.displayManager.sessionPackages = [jellyfin-kiosk-session];

  systemd.user.targets.jellyfin-kiosk-session = {
    description = "Jellyfin session";
    bindsTo = ["graphical-session.target"];
    wants = ["graphical-session-pre.target"];
    after = ["graphical-session-pre.target"];
  };
}
