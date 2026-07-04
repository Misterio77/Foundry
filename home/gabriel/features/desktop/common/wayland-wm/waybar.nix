{
  outputs,
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  gpgCmds = import ../../../cli/gpg-commands.nix { inherit pkgs config lib; };
  commonDeps = with pkgs; [coreutils gnugrep systemd];
  # Function to simplify making waybar outputs
  mkScript = {
    name ? "script",
    deps ? [],
    script ? "",
  }:
    lib.getExe (pkgs.writeShellApplication {
      inherit name;
      text = script;
      runtimeInputs = commonDeps ++ deps;
    });
  # Specialized for JSON outputs
  mkScriptJson = {
    name ? "script",
    deps ? [],
    script ? "",
    text ? "",
    tooltip ? "",
    alt ? "",
    class ? "",
    percentage ? "",
  }:
    mkScript {
      inherit name;
      deps = [pkgs.jq] ++ deps;
      script = ''
        ${script}
        jq -cn \
          --arg text "${text}" \
          --arg tooltip "${tooltip}" \
          --arg alt "${alt}" \
          --arg class "${class}" \
          --arg percentage "${percentage}" \
          '{text:$text,tooltip:$tooltip,alt:$alt,class:$class,percentage:$percentage}'
      '';
    };

  swayCfg = config.wayland.windowManager.sway;
  hyprlandCfg = config.wayland.windowManager.hyprland;
in {
  systemd.user.services.waybar = {
    Unit = {
      # Let it try to start a few more times
      StartLimitBurst = 30;
      # Reload instead of restarting
      X-Restart-Triggers = lib.mkForce [];
      X-SwitchMethod = "reload";
    };
  };
  programs.waybar = {
    enable = true;
    package = pkgs.waybar.overrideAttrs (oa: {
      mesonFlags = (oa.mesonFlags or []) ++ ["-Dexperimental=true"];
    });
    systemd.enable = true;
    settings = {
      primary = {
        exclusive = false;
        passthrough = false;
        height = 40;
        margin = "15";
        position = "top";
        modules-left =
          ["custom/menu"]
          ++ (lib.optionals swayCfg.enable [
            "sway/workspaces"
            "sway/mode"
          ])
          ++ (lib.optionals hyprlandCfg.enable [
            "hyprland/workspaces"
            "hyprland/submap"
          ]) ++ [
            "custom/currentplayer"
            "custom/player"
        ];

        modules-right = [
          "tray"
          "custom/gpg-status"
          "custom/sync-status"
          "custom/unread-mail"
          "custom/next-event"
          "network"
          "custom/rfkill"
          "battery"
          "pulseaudio"
          "clock"
        ];

        clock = {
          format = "{:%H:%M %d/%m}";
          on-click-left = "mode";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
        };

        cpu = {
          interval = 5;
          format = "  {usage}%";
        };
        "custom/gpu" = {
          interval = 5;
          exec = mkScript {script = "cat /sys/class/drm/card*/device/gpu_busy_percent | head -1";};
          format = "󰒋  {}%";
        };
        memory = {
          format = "  {}%";
          interval = 5;
        };

        "pulseaudio" = {
          format = "{icon}{format_source}";
          format-bluetooth = "{icon} 󰂯{format_source}";
          format-source = "";
          format-source-muted = " 󰍭";
          format-icons = {
            default-muted = "󰸈";
            default = [
              "󰕿"
              "󰖀"
              "󰖀"
              "󰕾"
            ];
            headphone-muted = "󰟎";
            headphone = "󰋋";
            headset-muted = "󰋐";
            headset = "󰋎";
          };
          on-click = lib.getExe pkgs.pavucontrol;
        };
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰒳";
            deactivated = "󰒲";
          };
        };
        battery = {
          interval = 10;
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          format = "{icon}";
          format-charging = "󰂄";
          tooltip-format = "{capacity}% ({time})";
          onclick = "";
        };
        "sway/window" = {
          max-length = 20;
        };
        network = {
          interval = 3;
          format-wifi = "󰖩";
          format-ethernet = "󰈀";
          format-disconnected = "";
          tooltip-format = ''
            {essid}
            {ifname}
            {ipaddr}/{cidr}
            Up: {bandwidthUpBits}
            Down: {bandwidthDownBits}'';
        };
        "custom/menu" = {
          return-type = "json";
          exec = mkScriptJson {
            tooltip = "$USER@$HOSTNAME";
            alt = "$(grep LOGO /etc/os-release | cut -d = -f2 | cut -d '\"' -f2)";
          };
          format = "{icon}";
          format-icons = {
            "nix-snowflake" = "";
            "ubuntu-logo" = "󰕈";
          };
        };
        "custom/unread-mail" = {
          interval = 10;
          return-type = "json";
          exec = mkScriptJson {
            deps = [pkgs.findutils pkgs.gawk];
            script = ''
              inbox_count="$(find ~/Mail/*/Inbox/new -type f | cut -d / -f5 | uniq -c | awk '{$1=$1};1')"
              if [ -z "$inbox_count" ]; then
                status="read"
                inbox_count="No new mail!"
              else
                status="unread"
              fi
            '';
            tooltip = "$inbox_count";
            alt = "$status";
          };
          format = "{icon}";
          format-icons = {
            "read" = "󰇯";
            "unread" = "󰇮";
          };
          on-click = mkScript { deps = [pkgs.handlr-regex]; script = "handlr launch x-scheme-handler/mailto"; };
        };
        "custom/next-event" = {
          interval = 10;
          return-type = "json";
          exec = mkScriptJson {
            deps = [config.programs.khal.package pkgs.gnugrep];
            script = ''
              events="$(khal list now tomorrow --json title --json start-time | jq '.[] | "\(."start-time") \(.title)"' -r)"
              count="$(printf "%s" "$events" | grep -c "^" || true)"
              if [ "$count" == 0 ]; then
                status="no-event"
                events="No events!"
              else
                if test -n "$(khal list now 10m --json title --json start-time | jq '.[] | select(."start-time" != "") | "\(.title)"' -r)"; then
                  status="has-close-event"
                else
                  status="has-event"
                fi
              fi
            '';
            alt = "$status";
            tooltip = "$events";
          };
          format = "{icon}";
          format-icons = {
            has-event = "󰃭";
            has-close-event = "󰨱";
            no-event = "󰃮";
          };
          on-click = mkScript { deps = [pkgs.handlr-regex]; script = "handlr launch text/calendar"; };
        };
        "custom/gpg-status" = {
          interval = 3;
          return-type = "json";
          exec = mkScriptJson {
            script = ''
              if ${gpgCmds.isUnlocked}; then
                status="unlocked"
                tooltip="GPG is unlocked"
              else
                status="locked"
                tooltip="GPG is locked"
              fi
            '';
            alt = "$status";
            tooltip = "$tooltip";
          };
          on-click = mkScript { script = ''if ${gpgCmds.isUnlocked}; then ${gpgCmds.lock}; else ${gpgCmds.unlock}; fi''; };
          format = "{icon}";
          format-icons = {
            locked = "󰌾";
            unlocked = "󰿆";
          };
        };
        "custom/sync-status" = {
          interval = 3;
          return-type = "json";
          exec-if = gpgCmds.isUnlocked;
          exec = mkScriptJson {
            script = ''
              results="$(systemctl --user show mbsync.service vdirsyncer.service --property Id,Result,ActiveState)"
              last_sync="$(date --date="$(systemctl --user show mbsync.timer vdirsyncer.timer --property LastTriggerUSec --value | head -1)" +%H:%M)"
              if grep -q ActiveState=activating <<< "$results"; then
                tooltip="Syncing calendars and mail"
                status="activating"
              elif grep -q Result=exit-code <<< "$results"; then
                tooltip="Failed to sync calendars and mail"
                status="failed"
              elif grep -q Result=exec-condition <<< "$results"; then
                tooltip="Sync is paused as GPG key is not available"
                status="condition"
              elif [ "$(grep -c Result=success <<< "$results")" == 2 ]; then
                tooltip="Calendars and mail are synced"
                status="success"
              else
                tooltip="Unknown sync state"
                status="unknown"
              fi
              tooltip+=$'\n'"Last sync: $last_sync"
            '';
            tooltip = "$tooltip";
            alt = "$status";
          };
          on-click = mkScript { script = "systemctl --user start mbsync.service vdirsyncer.service"; };
          format = "{icon}";
          format-icons = {
            activating= "󰘿";
            failed = "󰧠";
            condition = "󱇱";
            success = "󰅠";
            unknown = "󰨹";
          };
        };
        "custom/currentplayer" = {
          interval = 2;
          return-type = "json";
          exec = mkScriptJson {
            deps = [pkgs.playerctl];
            script = ''
              all_players=$(playerctl -l 2>/dev/null)
              selected_player="$(playerctl status -f "{{playerName}}" 2>/dev/null || true)"
              clean_player="$(echo "$selected_player" | cut -d '.' -f1)"
            '';
            alt = "$clean_player";
            tooltip = "$all_players";
          };
          format = "{icon}{text}";
          format-icons = {
            "" = " ";
            "Celluloid" = "󰎁 ";
            "spotify" = "󰓇 ";
            "ncspot" = "󰓇 ";
            "qutebrowser" = "󰖟 ";
            "firefox" = " ";
            "discord" = " 󰙯 ";
            "sublimemusic" = " ";
            "kdeconnect" = "󰄡 ";
            "chromium" = " ";
          };
        };
        "custom/player" = {
          exec-if = mkScript {
            deps = [pkgs.playerctl];
            script = ''
              selected_player="$(playerctl status -f "{{playerName}}" 2>/dev/null || true)"
              playerctl status -p "$selected_player" 2>/dev/null
            '';
          };
          exec = mkScript {
            deps = [pkgs.playerctl];
            script = ''
              selected_player="$(playerctl status -f "{{playerName}}" 2>/dev/null || true)"
              playerctl metadata -p "$selected_player" \
                --format '{"text": "{{artist}} - {{title}}", "alt": "{{status}}", "tooltip": "{{artist}} - {{title}} ({{album}})"}' 2>/dev/null
            '';
          };
          return-type = "json";
          interval = 2;
          max-length = 30;
          format = "{icon} {text}";
          format-icons = {
            "Playing" = "󰐊";
            "Paused" = "󰏤 ";
            "Stopped" = "󰓛";
          };
          on-click = mkScript {
            deps = [pkgs.playerctl];
            script = "playerctl play-pause";
          };
        };
        "custom/rfkill" = {
          interval = 3;
          exec-if = mkScript {
            deps = [pkgs.util-linux];
            script = "rfkill list wifi | grep yes -q";
          };
          exec = "echo 󰀝";
        };
      };
    };
    # Cheatsheet:
    # x -> all sides
    # x y -> vertical, horizontal
    # x y z -> top, horizontal, bottom
    # w x y z -> top, right, bottom, left
    style = let
      inherit (inputs.nix-colors.lib.conversions) hexToRGBString;
      inherit (config.colorscheme) colors;
      toRGBA = color: opacity: "rgba(${hexToRGBString "," (lib.removePrefix "#" color)},${opacity})";
    in
      /*
      css
      */
      ''
        * {
          font-family: ${config.fontProfiles.regular.name}, ${config.fontProfiles.monospace.name};
          font-size: 12pt;
          padding: 0;
          margin: 0 0.4em;
        }

        window#waybar {
          padding: 0;
          background-color: transparent;
          color: ${colors.on_surface};
        }
        .modules-left {
          background-color: ${toRGBA colors.surface "0.8"};
          margin-left: 0;
          border-radius: 0.5em;
          border-right: solid 0.4em ${colors.surface};
        }
        .modules-right {
          background-color: ${toRGBA colors.surface "0.8"};
          margin-right: 0;
          border-radius: 0.5em;
          border-left: solid 0.4em ${colors.surface};
        }

        #workspaces button {
          color: ${colors.on_surface};
          padding-left: 0.2em;
          padding-right: 0.2em;
          margin-top: 0.15em;
          margin-bottom: 0.15em;
          margin-left: 0.1em;
          margin-right: 0.1em;
        }
        #workspaces button.hidden {
          background-color: ${colors.surface};
          color: ${colors.on_surface_variant};
        }
        #workspaces button.focused,
        #workspaces button.active {
          background-color: ${colors.primary};
          color: ${colors.on_primary};
        }

        #custom-menu {
          background-color: ${colors.surface_container};
          color: ${colors.primary};
          padding-right: 1.5em;
          padding-left: 1em;
          margin-left: 0;
          border-radius: 0.5em;
        }
        #clock {
          background-color: ${colors.surface_container};
          color: ${colors.primary};
          padding-right: 0.8em;
          padding-left: 0.7em;
          margin-right: 0;
          border-radius: 0.5em;
        }

        #custom-player {
          padding-left: 0;
          margin-left: 0;
          margin-right: 1em;
        }
        #custom-currentplayer {
          padding-right: 0;
          margin-left: 1em;
        }
        #tray {
          color: ${colors.on_surface};
        }
      '';
  };
}
