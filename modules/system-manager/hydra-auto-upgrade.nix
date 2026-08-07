{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.system.hydraAutoUpgrade;
  cached-system-manager = pkgs.writeShellApplication {
    name = "cached-system-manager";
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

      # Unlike NixOS there is no /run/current-system active pointer and no
      # boot-time reactivation: the registered profile is the single source of
      # truth, since `switch` always registers and activates together.
      profile="/nix/var/nix/profiles/system-manager-profiles/system-manager"

      echo "Building $path" >&2
      nix build --no-link "$path"

      if [ "$action" == "diff" ]; then
        if [ "$(readlink -f "$profile")" != "$path" ]; then
          nvd --color=always diff "$profile" "$path"
        else
          echo "No changes"
        fi
      fi

      if [ "$action" == "switch" ]; then
        if [ "$(readlink -f "$profile")" == "$path" ]; then
          echo "Already running $path" >&2
        else
          echo "Changes to apply now:"
          nvd --color=always diff "$profile" "$path"

          echo "Activating configuration" >&2
          "$path/bin/register-profile"
          "$path/bin/activate"
        fi
      fi
    '';
  };
in {
  options = {
    system.hydraAutoUpgrade = {
      enable = lib.mkEnableOption "periodic hydra-based auto upgrade";
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
    systemd.services.system-manager-upgrade = {
      description = "System Manager Upgrade";
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig.Type = "oneshot";

      script = "${lib.getExe cached-system-manager} switch ${cfg.jobset} ${cfg.job}";
      startAt = cfg.dates;
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };
    # Make script available for admin usage
    environment.systemPackages = [cached-system-manager];
  };
}
