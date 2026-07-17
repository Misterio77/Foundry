{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.system.hydraAutoUpgrade;
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
      jobset="''${2:-${cfg.jobset}}"
      job="''${3:-${cfg.job}}"

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

      latest="$(fetch_json "${cfg.instance}/job/${cfg.project}/$jobset/$job/latest")"
      eval="$(jq -er '.jobsetevals[0] | select((type == "number") or (type == "string")) | tostring' <<<"$latest")"
      path="$(jq -er '.buildoutputs.out.path | select(type == "string" and startswith("/nix/store/"))' <<<"$latest")"

      eval_data="$(fetch_json "${cfg.instance}/eval/$eval")"
      new_flake="$(jq -er '.flake | select(type == "string" and length > 0)' <<<"$eval_data")"
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
    system.hydraAutoUpgrade = {
      enable = lib.mkEnableOption "periodic hydra-based auto upgrade";
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
        example = "https://hydra.m7.rs";
      };
      project = lib.mkOption {
        type = lib.types.str;
        example = "foundry";
      };
      jobset = lib.mkOption {
        type = lib.types.str;
        example = "main";
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
          hydraAutoUpgrade and autoUpgrade are mutually exclusive.
        '';
      }
    ];
    systemd.services.nixos-upgrade = {
      description = "NixOS Upgrade";
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig.Type = "oneshot";

      script = "${lib.getExe cached-nixos-rebuild} ${cfg.operation} ${cfg.jobset} ${cfg.job}";
      startAt = cfg.dates;
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };
    # Make script available for admin usage
    environment.systemPackages = [cached-nixos-rebuild];
  };
}
