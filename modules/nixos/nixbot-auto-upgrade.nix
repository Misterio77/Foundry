{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.system.nixbotAutoUpgrade;
  cached-nixos-rebuild = pkgs.writeShellApplication {
    name = "cached-nixos-rebuild";
    runtimeInputs = with pkgs; [
      config.nix.package.out
      config.programs.ssh.package
      coreutils
      curl
      gitMinimal
      gnutar
      gzip
      jq
      nvd
    ];
    text = ''
      action="''${1:-build}"
      job="''${2:-${cfg.job}}"

      fetch_json() {
        curl \
          --silent \
          --show-error \
          --fail-with-body \
          --location \
          --header 'accept: application/json' \
          --connect-timeout 10 \
          --max-time 30 \
          --retry 3 \
          --retry-all-errors \
          --retry-max-time 120 \
          "$1"
      }

      current_ts="$(nix flake metadata "self" --json | jq -er '.lastModified | select(type == "number")')"
      echo "Current flake modified at: $(date -d @"$current_ts")" >&2

      history="$(fetch_json "${cfg.instance}/api/repos/${cfg.project}/attrs/$job")"
      latest="$(jq -ec --arg branch ${lib.escapeShellArg cfg.branch} '
        [.[] | select(.branch == $branch and .status == "succeeded")]
        | max_by(.build_number) | select(. != null)
      ' <<<"$history")"
      revision="$(jq -er '.commit_sha | select(test("^[0-9a-f]{40}$"))' <<<"$latest")"
      path="$(jq -er '.outputs.out | select(test("^/nix/store/[0-9a-z]{32}-[^/]+$"))' <<<"$latest")"

      new_flake=${lib.escapeShellArg cfg.source}"&rev=$revision"
      echo "New flake: $new_flake" >&2
      new_ts="$(nix flake metadata "$new_flake" --json | jq -er '.lastModified | select(type == "number")')"
      echo "Modified at: $(date -d @"$new_ts")" >&2

      if ! "''${IGNORE_TIMESTAMP:-false}" && ! [ "$new_ts" -gt "$current_ts" ]; then
        echo "Skipping upgrade, not newer. Set IGNORE_TIMESTAMP=true to skip this check." >&2
        exit 0
      fi

      profile="/nix/var/nix/profiles/system"
      current="/run/current-system"

      echo "Building $path" >&2
      nix build --no-link "$path"

      if [ "$action" == "diff" ]; then
        if [ "$(readlink -f "$current")" != "$path" ]; then
          nvd --color=always diff "$current" "$path"
        else
          echo "No changes"
        fi
      fi

      if [ "$action" == "switch" ] || [ "$action" == "test" ]; then
        if [ "$(readlink -f "$current")" == "$path" ]; then
          echo "Already running $path" >&2
        else
          echo "Changes to apply now:"
          nvd --color=always diff "$current" "$path"

          echo "Activating configuration" >&2
          "$path/bin/switch-to-configuration" test
        fi
      fi

      if [ "$action" == "switch" ] || [ "$action" == "boot" ]; then
        if [ "$(readlink -f "$profile")" == "$path" ]; then
          echo "Already set to boot $path" >&2
        else
          echo "Setting profile" >&2
          nix build --no-link --profile "$profile" "$path"

          echo "Adding to bootloader" >&2
          "$path/bin/switch-to-configuration" boot

          if [ "$(readlink -f "$current")" != "$(readlink -f "$profile")" ]; then
            echo "Changes to apply after reboot:"
            nvd --color=always diff "$current" "$profile"
          else
            echo "No pending boot change"
          fi
        fi
      fi
    '';
  };
in {
  options = {
    system.nixbotAutoUpgrade = {
      enable = lib.mkEnableOption "periodic Nixbot-based auto upgrade";
      operation = lib.mkOption {
        type = lib.types.enum ["switch" "boot"];
        default = "switch";
      };
      dates = lib.mkOption {
        type = lib.types.str;
        default = "04:40";
        example = "daily";
      };

      instance = lib.mkOption {
        type = lib.types.str;
        example = "https://ci.m7.rs";
      };
      project = lib.mkOption {
        type = lib.types.str;
        example = "pull_based/m7/Foundry";
        description = "Nixbot project API path: forge/owner/repository.";
      };
      branch = lib.mkOption {
        type = lib.types.str;
        default = "main";
      };
      source = lib.mkOption {
        type = lib.types.str;
        description = "Git flake URL for source metadata, including query parameters but no revision.";
      };
      job = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> !config.system.autoUpgrade.enable;
        message = ''
          nixbotAutoUpgrade and autoUpgrade are mutually exclusive.
        '';
      }
    ];
    systemd.services.nixos-upgrade = {
      description = "NixOS Upgrade";
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig.Type = "oneshot";

      script = "${lib.getExe cached-nixos-rebuild} ${cfg.operation} ${cfg.job}";
      startAt = cfg.dates;
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };
    system.build.cached-nixos-rebuild = cached-nixos-rebuild;
    environment.systemPackages = [cached-nixos-rebuild];
  };
}
