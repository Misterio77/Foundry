{
  lib,
  config,
  pkgs,
  ...
}: let
  rgb = color: "rgb(${lib.removePrefix "#" color})";
  rgba = color: alpha: "rgba(${lib.removePrefix "#" color}${alpha})";

  swayosd = {
    brightness = "swayosd-client --brightness +0";
    output-volume = "swayosd-client --output-volume +0";
    input-volume = "swayosd-client --input-volume +0";
    caps-lock = "sleep 0.2 && swayosd-client --caps-lock";
  };
  grimblast = lib.getExe pkgs.grimblast;
  pactl = lib.getExe' pkgs.pulseaudio "pactl";
  defaultApp = type: "${lib.getExe pkgs.handlr-regex} launch ${type}";
  tmuxSessionPicker = pkgs.writeShellScript "tmux-session-picker" ''
    set -euo pipefail

    tmux="${config.programs.tmux.package}/bin/tmux"
    wofi="${lib.getExe config.programs.wofi.package}"
    handlr="${lib.getExe pkgs.handlr-regex}"

    choice=$(
      {
        printf '%s\n' "new session"
        "$tmux" list-sessions -F '#{?session_grouped,#{session_group},#{session_name}}' 2>/dev/null | sort -u || true
      } | "$wofi" -S dmenu --cache-file /dev/null -p 'tmux session'
    )

    open_view() {
      target="$1"
      safe_target="$(printf '%s' "$target" | tr -c '[:alnum:]_-' '_')"
      view="''${safe_target}-view-$$"

      exec "$handlr" launch x-scheme-handler/terminal -- \
        -e "$tmux" new-session -d -t "$target" -s "$view" \; \
        set-option -t "$view" destroy-unattached on \; \
        attach-session -t "$view"
    }

    case "$choice" in
      "") exit 0 ;;
      "new session") exec "$handlr" launch x-scheme-handler/terminal -- -e "$tmux" new-session ;;
      *)
        if "$tmux" has-session -t "$choice" 2>/dev/null; then
          open_view "$choice"
        else
          exec "$handlr" launch x-scheme-handler/terminal -- -e "$tmux" new-session -s "$choice"
        fi
        ;;
    esac
  '';
  remote = lib.getExe (pkgs.writeShellScriptBin "remote" ''
    socket="$(basename "$(find ~/.ssh -name 'master-gabriel@*' | head -1 | cut -d ':' -f1)")"
    host="''${socket#master-}"
    ssh "$host" "$@"
  '');
in {
  imports = [
    ../common
    ../common/wayland-wm

    ./basic-binds.nix
    ./hyprbars.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
  ];

  home.pointerCursor.hyprcursor.enable = true;

  xdg.portal = {
    extraPortals = [(pkgs.xdg-desktop-portal-hyprland.override {hyprland = config.wayland.windowManager.hyprland.package;})];
    config.hyprland = {
      default = ["hyprland" "gtk"];
    };
  };

  home.packages = [
    pkgs.grimblast
    pkgs.hyprpicker
  ];

  home.exportedSessionPackages = [config.wayland.windowManager.hyprland.package];

  wayland.windowManager.hyprland = {
    enable = true;
    package = config.lib.nixGL.wrap (pkgs.hyprland.override {
      wrapRuntimeDeps = false;
    });
    systemd = {
      enable = true;
      # Same as default, but stop graphical-session too
      extraCommands = lib.mkBefore [
        "systemctl --user stop graphical-session.target"
        "systemctl --user start hyprland-session.target"
      ];
      variables = [
        "DISPLAY"
        "HYPRLAND_INSTANCE_SIGNATURE"
        "WAYLAND_DISPLAY"
        "XDG_CURRENT_DESKTOP"
      ];
    };

    importantPrefixes = [
      "$"
      "bezier"
      "name"
      "source"
      "exec-once"
    ];

    configType = "hyprlang";
    settings = {
      general = {
        gaps_in = 15;
        gaps_out = "70,20,20,20"; # 70 = 15 (waybar margin) + 20 (waybar height) + 15 (gaps_in)
        border_size = 2;
        "col.active_border" = rgba config.colorscheme.colors.primary "ee";
        "col.inactive_border" = rgba config.colorscheme.colors.surface "aa";
        # allow_tearing = true;
      };
      cursor.inactive_timeout = 4;
      group = {
        "col.border_active" = rgba config.colorscheme.colors.primary "ee";
        "col.border_inactive" = rgba config.colorscheme.colors.surface "aa";
        groupbar.font_size = 11;
      };
      binds = {
        movefocus_cycles_fullscreen = false;
      };
      input = {
        kb_layout = "us_intl";
        touchpad = {
          disable_while_typing = false;
          natural_scroll = true;
        };
      };
      dwindle = {
        split_width_multiplier = 1.35;
      };
      gesture = [
        "3, horizontal, workspace"
      ];
      misc = {
        close_special_on_empty = true;
        focus_on_activate = true;
        # Unfullscreen when opening something
        on_focus_under_fullscreen = 2;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        disable_hyprland_guiutils_check = true;
        enable_swallow = true;
        swallow_regex = "(?i)(${lib.concatMapStringsSep "|" (lib.removeSuffix ".desktop") config.xdg.mimeApps.defaultApplications."x-scheme-handler/terminal"})";
      };
      windowrule = let
        sweethome3d-tooltips = "match:title win[0-9], match:class com-eteks-sweethome3d-SweetHome3DBootstrap";
        steamGame = "match:class steam_app_[0-9]*";
        wineTray = "match:class explorer.exe";
        rsiLauncher = "match:class rsi launcher.exe";
        steamBigPicture = "match:title Steam Big Picture Mode";
        firefoxPictureInPicture = "match:class firefox, match:title Picture-in-Picture";
        floatingVlc = "match:float 1, match:class vlc";
      in
        [
          "idle_inhibit focus, match:fullscreen_state_internal 2 *"
          "no_initial_focus on, ${sweethome3d-tooltips}"

          "immediate on, ${steamGame}"

          "workspace special silent, ${wineTray}"

          "tile on, ${rsiLauncher}"

          "fullscreen on, ${steamBigPicture}"

          "float on, ${firefoxPictureInPicture}"
          "pin on, ${firefoxPictureInPicture}"

          "pin on, ${floatingVlc}"
        ]
        ++ (lib.mapAttrsToList (
            name: colors: "border_color ${rgba colors.primary "ee"} ${rgba colors.primary_container "aa"}, match:title \\[${name}\\].*"
          )
          config.colorscheme.hosts);
      layerrule = [
        "animation fade, match:namespace hyprpicker"
        "animation fade, match:namespace selection"
        "animation fade, match:namespace hyprpaper"

        "animation fade, match:namespace waybar"
        "blur on, match:namespace waybar"
        "ignore_alpha 0, match:namespace waybar"

        "blur on, match:namespace notifications"
        "ignore_alpha 0, match:namespace notifications"

        "blur on, match:namespace wofi"
        "ignore_alpha 0, match:namespace wofi"

        "no_anim on, match:namespace wallpaper"

        "above_lock 2, match:namespace swayosd"
      ];

      decoration = {
        active_opacity = 1.0;
        inactive_opacity = 0.85;
        fullscreen_opacity = 1.0;
        rounding = 10;
        rounding_power = 4;
        blur = {
          enabled = false;
          size = 4;
          passes = 3;
          new_optimizations = true;
          ignore_opacity = true;
          popups = true;
        };
        shadow = {
          enabled = false;
          offset = "3 3";
          range = 12;
          color = "0x44000000";
          color_inactive = "0x66000000";
        };
      };
      animations = {
        enabled = true;
        bezier = [
          "easeout,0.5, 1, 0.9, 1"
          "easeoutback,0.34,1.22,0.65,1"
        ];

        animation = [
          "fadeIn,1,3,easeout"
          "fadeLayersIn,1,3,easeout"
          "fadeOut,1,3,easeout"
          "fadeLayersOut,1,3,easeout"
          "fadeSwitch,1,2,easeout"
          "fadeDim,1,3,easeout"
          "fadeShadow,1,2,easeout"
          "border,1,2,easeout"

          "layersIn,1,3,easeoutback,slide"
          "layersOut,1,3,easeoutback,slide"

          "windowsOut,1,3,easeout,slide"
          "windowsMove,1,3,easeoutback"
          "windowsIn,1,3,easeoutback,slide"

          "workspaces,1,2.5,easeoutback,slidefade"
        ];
      };

      exec = [
        "hyprctl setcursor ${config.gtk.cursorTheme.name} ${toString config.gtk.cursorTheme.size}"
      ];

      # Will repeat when h[e]ld, also works when [l]ocked
      bindel = [
        # Brightness control
        ",XF86MonBrightnessUp,exec,brightnessctl s +10%; ${swayosd.brightness}"
        ",XF86MonBrightnessDown,exec,brightnessctl s 10%-; ${swayosd.brightness}"
        # Volume
        ",XF86AudioRaiseVolume,exec,${pactl} set-sink-volume @DEFAULT_SINK@ +5%; ${swayosd.output-volume}"
        ",XF86AudioLowerVolume,exec,${pactl} set-sink-volume @DEFAULT_SINK@ -5%; ${swayosd.output-volume}"
        "SHIFT,XF86AudioRaiseVolume,exec,${pactl} set-source-volume @DEFAULT_SOURCE@ +5%; ${swayosd.input-volume}"
        "SHIFT,XF86AudioLowerVolume,exec,${pactl} set-source-volume @DEFAULT_SOURCE@ -5%; ${swayosd.input-volume}"
      ];
      # Also works when [l]ocked
      bindl =
        [
          # Mute volume
          ",XF86AudioMute,exec,${pactl} set-sink-mute @DEFAULT_SINK@ toggle; ${swayosd.output-volume}"
          "SHIFT,XF86AudioMute,exec,${pactl} set-source-mute @DEFAULT_SOURCE@ toggle; ${swayosd.input-volume}"
          ",XF86AudioMicMute,exec,${pactl} set-source-mute @DEFAULT_SOURCE@ toggle; ${swayosd.input-volume}"
          # Show caps lock
          ",Caps_Lock,exec,${swayosd.caps-lock}"
        ]
        ++ (
          let
            playerctl = lib.getExe' config.services.playerctld.package "playerctl";
            playerctld = lib.getExe' config.services.playerctld.package "playerctld";
          in
            lib.optionals config.services.playerctld.enable [
              # Media control
              ",XF86AudioNext,exec,${playerctl} next"
              ",XF86AudioPrev,exec,${playerctl} previous"
              ",XF86AudioPlay,exec,${playerctl} play-pause"
              ",XF86AudioStop,exec,${playerctl} stop"
              "SHIFT,XF86AudioNext,exec,${playerctld} shift"
              "SHIFT,XF86AudioPrev,exec,${playerctld} unshift"
              "SHIFT,XF86AudioPlay,exec,systemctl --user restart playerctld"
            ]
        );

      # Normal bindings
      bind =
        [
          # Rename workspace
          "SUPER,r,exec,${pkgs.writeShellScript "rename" ''
            workspace="$(hyprctl activeworkspace -j)"
            id="$(jq -r .id <<< "$workspace")"
            prefix="$id - "
            name="$(jq -r .name <<< "$workspace")"
            name="''${name#"$prefix"}" # Remove prefix
            entry="$(GSK_RENDERER=cairo ${lib.getExe pkgs.zenity} --entry --title "Rename Workspace" --entry-text="$name")"
            if [ -z "$entry" ] || [ "$entry" == "$id" ]; then
              new_name="$id"
            else
              new_name="$prefix$entry"
            fi
            hyprctl dispatch renameworkspace "$id" "$new_name"
          ''}"
          # Program bindings
          "SUPER,Return,exec,${defaultApp "x-scheme-handler/terminal"}"
          "SUPER,e,exec,${defaultApp "text/plain"}"
          "SUPER,b,exec,${defaultApp "x-scheme-handler/https"}"
          "SUPERALT,Return,exec,${remote} ${defaultApp "x-scheme-handler/terminal"}"
          "SUPERALT,e,exec,${remote} ${defaultApp "text/plain"}"
          "SUPERALT,b,exec,${remote} ${defaultApp "x-scheme-handler/https"}"
          # Screenshotting
          ",Print,exec,${grimblast} --freeze copy area"
          "SHIFT,Print,exec,${grimblast} --freeze copy output"
        ]
        ++
        # Notification manager
        (
          let
            makoctl = lib.getExe' config.services.mako.package "makoctl";
          in
            lib.optionals config.services.mako.enable [
              "SUPER,w,exec,${makoctl} dismiss"
              "SUPERSHIFT,w,exec,${makoctl} restore"
            ]
        )
        ++
        # Launcher
        (
          let
            wofi = lib.getExe config.programs.wofi.package;
          in
            lib.optionals config.programs.wofi.enable [
              "SUPER,x,exec,${wofi} -S drun -x 10 -y 10 -W 25% -H 60%"
              "SUPER,s,exec,specialisation $(specialisation | ${wofi} -S dmenu)"
              "SUPER,d,exec,${wofi} -S run"
              "SUPER,space,exec,${tmuxSessionPicker}"

              "SUPERALT,x,exec,${remote} ${wofi} -S drun -x 10 -y 10 -W 25% -H 60%"
              "SUPERALT,d,exec,${remote} ${wofi} -S run"
            ]
            ++ (
              let
                pass-wofi = lib.getExe (pkgs.pass-wofi.override {pass = config.programs.password-store.package;});
              in
                lib.optionals config.programs.password-store.enable [
                  ",XF86Calculator,exec,${pass-wofi}"
                  "SHIFT,XF86Calculator,exec,${pass-wofi} fill"

                  "SUPER,semicolon,exec,${pass-wofi}"
                  "SHIFTSUPER,semicolon,exec,${pass-wofi} fill"
                ]
            )
            ++ (
              let
                cliphist = lib.getExe config.services.cliphist.package;
              in
                lib.optionals config.services.cliphist.enable [
                  ''SUPER,c,exec,selected=$(${cliphist} list | ${wofi} -S dmenu) && echo "$selected" | ${cliphist} decode | wl-copy''
                ]
            )
            ++ (
              let
                # Save to image and share it to device, if png; else share as text to clipboard.
                share-kdeconnect = lib.getExe (pkgs.writeShellScriptBin "kdeconnect-share" ''
                  type="$(wl-paste -l | head -1)"
                  device="$(kdeconnect-cli -a --id-only | head -1)"
                  if [ "$type" == "image/png" ]; then
                    path="$(mktemp XXXXXXX.png)"
                    wl-paste > "$path"
                    output="$(kdeconnect-cli --share "$path" -d "$device")"
                  else
                    output="$(kdeconnect-cli --share-text "$(wl-paste)" -d "$device")"
                  fi
                  notify-send -i kdeconnect "$output"
                '');
              in
                lib.optionals config.services.kdeconnect.enable [
                  "SUPER,v,exec,${share-kdeconnect}"
                ]
            )
        );

      monitor = map (m: "${m.name},${
        if m.enabled
        then "${toString m.width}x${toString m.height}@${toString m.refreshRate},${m.position},${toString m.scale}"
        else "disable"
      }") (config.monitors);

      workspace = map (m: "${m.workspace},monitor:${m.name}") (
        lib.filter (m: m.enabled && m.workspace != null) config.monitors
      );
    };
    # This is order sensitive, so it has to come here.
    extraConfig = ''
      # Passthrough mode (e.g. for VNC)
      bind=SUPER,esc,submap,passthrough
      submap=passthrough
      bind=SUPER,esc,submap,reset
      submap=reset
    '';
  };
}
