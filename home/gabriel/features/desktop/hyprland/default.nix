{
  lib,
  config,
  pkgs,
  ...
}: let
  hyprland = config.wayland.windowManager.hyprland;
  renameWorkspace = pkgs.writeShellScript "rename-workspace" ''
    entry=$(GSK_RENDERER=cairo ${lib.getExe pkgs.zenity} --entry \
      --title "Rename Workspace" --entry-text="$2") || exit 0

    # Quote arbitrary input as a Lua long string without blocking the compositor.
    delimiter="="
    while [[ "$entry" == *"]$delimiter]"* ]]; do delimiter+="="; done
    ${hyprland.finalPackage}/bin/hyprctl eval "require('bindings').rename_workspace($1, [''${delimiter}[
    $entry]''${delimiter}])"
  '';
  shareClipboard = pkgs.writeShellScript "kdeconnect-share-clipboard" ''
    device="$(kdeconnect-cli -a --id-only | head -1)"
    if wl-paste -l | grep -qx image/png; then
      path="$(mktemp --suffix=.png)"
      wl-paste --type image/png > "$path"
      output="$(kdeconnect-cli --share "$path" -d "$device")"
    else
      output="$(kdeconnect-cli --share-text "$(wl-paste)" -d "$device")"
    fi
    notify-send -i kdeconnect "$output"
  '';
  data = {
    colors = lib.getAttrs ["surface" "primary" "on_primary" "red" "yellow" "green"] config.colorscheme.colors;
    hosts = lib.mapAttrs (_: lib.getAttrs ["primary" "primary_container" "on_primary" "on_primary_container"]) config.colorscheme.hosts;
    monitors = map (lib.getAttrs ["name" "enabled" "width" "height" "refreshRate" "position" "scale" "workspace"]) config.monitors;
    font = {inherit (config.fontProfiles.regular) name size;};
    commands = {
      handlr = lib.getExe pkgs.handlr-regex;
      grimblast = lib.getExe pkgs.grimblast;
      pactl = lib.getExe' pkgs.pulseaudio "pactl";
      renameWorkspace = toString renameWorkspace;
      hyprlock = lib.getExe config.programs.hyprlock.package;
      wofi =
        if config.programs.wofi.enable
        then lib.getExe config.programs.wofi.package
        else null;
      makoctl =
        if config.services.mako.enable
        then lib.getExe' config.services.mako.package "makoctl"
        else null;
      playerctl =
        if config.services.playerctld.enable
        then lib.getExe' config.services.playerctld.package "playerctl"
        else null;
      playerctld =
        if config.services.playerctld.enable
        then lib.getExe' config.services.playerctld.package "playerctld"
        else null;
      pass =
        if config.programs.password-store.enable
        then lib.getExe (pkgs.pass-wofi.override {pass = config.programs.password-store.package;})
        else null;
      cliphist =
        if config.services.cliphist.enable
        then lib.getExe config.services.cliphist.package
        else null;
      shareClipboard =
        if config.services.kdeconnect.enable
        then toString shareClipboard
        else null;
    };
  };
in {
  imports = [
    ../common
    ../common/wayland-wm
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
  ];

  home.pointerCursor.hyprcursor.enable = true;
  home.packages = [pkgs.grimblast pkgs.hyprpicker];
  # Export the ordinary session, not the package's unconfigured UWSM entry.
  home.exportedSessionPackages = [
    ((pkgs.linkFarm "hyprland-session" {
      "share/wayland-sessions/hyprland.desktop" = "${hyprland.finalPackage}/share/wayland-sessions/hyprland.desktop";
    }).overrideAttrs {passthru.providedSessions = ["hyprland"];})
  ];

  xdg.portal.config.hyprland.default = ["hyprland" "gtk"];
  # extraLuaFiles forces content early enough to recurse through cross-host colors.
  xdg.configFile."hypr/data.lua" = {
    text = "return ${lib.generators.toLua {} data}\n";
    onChange = config.xdg.configFile."hypr/hyprland.lua".onChange;
  };

  wayland.windowManager.hyprland = {
    enable = true;
    package = config.lib.nixGL.wrap (pkgs.hyprland.override {wrapRuntimeDeps = false;});
    configType = "lua";
    plugins = [(pkgs.hyprbars.override {hyprland = hyprland.finalPackage;})];
    extraLuaFiles = {
      settings = ./settings.lua;
      bindings = ./bindings.lua;
      rules = ./rules.lua;
      hyprbars = ./hyprbars.lua;
    };
  };
}
