{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.system.nixbotAutoUpgrade;
  pinnedGpg = pkgs.writeShellApplication {
    name = "pinned-gpg";
    runtimeInputs = [pkgs.gnupg pkgs.coreutils pkgs.gnugrep];
    text = ''
      umask 077
      home="$(mktemp -d)"
      trap 'rm -rf "$home"' EXIT
      gpg --no-options --homedir "$home" --batch --import ${lib.escapeShellArgs (map (key: "${key}") cfg.signingKeys)}
      status=0
      gpg --no-options --homedir "$home" --batch --no-auto-key-retrieve \
        --no-auto-key-import --trust-model always "$@" >"$home/status" || status=$?
      cat "$home/status"
      if grep -Eq '^\[GNUPG:\] (EXPKEYSIG|EXPSIG|REVKEYSIG|BADSIG|ERRSIG) ' "$home/status"; then
        exit 1
      fi
      exit "$status"
    '';
  };
  verifyCommit = pkgs.writeShellApplication {
    name = "verify-commit-signature";
    runtimeInputs = [pkgs.gitMinimal];
    text = ''
      export GIT_NO_REPLACE_OBJECTS=1
      git -c gpg.format=openpgp \
        -c gpg.openpgp.program=${lib.getExe pinnedGpg} \
        -c gpg.ssh.program=${pkgs.coreutils}/bin/false \
        -c gpg.x509.program=${pkgs.coreutils}/bin/false \
        -c gpg.minTrustLevel=undefined verify-commit -- "$@"
    '';
  };
  cached-nixos-rebuild = pkgs.writeShellApplication {
    name = "cached-nixos-rebuild";
    runtimeInputs = with pkgs; [
      config.nix.package.out
      coreutils
      curl
      gitMinimal
      jq
      nvd
      util-linux
    ];
    text = ''
      action="''${1:-build}"
      job="''${2:-${cfg.job}}"

      if [[ "$EUID" != 0 ]]; then
        echo "Source authorization requires a root-owned verification repository; run as root." >&2
        exit 1
      fi
      umask 077
      state="''${STATE_DIRECTORY:-/var/lib/nixbot-auto-upgrade}"
      mkdir -p "$state"
      chmod 700 "$state"
      exec 9>"$state/lock"
      flock --nonblock 9
      trap 'echo "Upgrade failed: candidate=''${revision:-unknown} tip=''${tip:-unknown} output=''${path:-unknown}" >&2' ERR
      export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1

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
      revision="$(jq -er '.commit_sha | select(type == "string") | select(test("^[0-9a-f]{40}$"))' <<<"$latest")"
      path="$(jq -er '.outputs.out | select(type == "string") | select(test("^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[a-zA-Z0-9+._?=-]+$"))' <<<"$latest")"
      echo "Candidate: $revision; selected output: $path" >&2

      export GIT_DIR="$state/repository"
      if [[ ! -d "$GIT_DIR" ]]; then
        git init --bare "$GIT_DIR"
      fi
      git check-ref-format ${lib.escapeShellArg "refs/heads/${cfg.branch}"}
      git -c http.sslVerify=true -c http.followRedirects=false \
        -c protocol.allow=never -c protocol.https.allow=always \
        fetch --no-tags ${lib.escapeShellArg cfg.source} \
        ${lib.escapeShellArg "+refs/heads/${cfg.branch}:refs/heads/authorized"}
      [[ "$(git rev-parse --is-shallow-repository)" == false ]]
      tip="$(git rev-parse --verify refs/heads/authorized)"
      echo "Fetched branch tip: $tip" >&2
      [[ "$(git cat-file -t "$revision")" == commit ]]
      git merge-base --is-ancestor "$revision" "$tip"
      echo "Branch authorization passed: $revision is reachable from $tip" >&2

      if [[ "''${IGNORE_SIGNATURE:-false}" == true ]]; then
        echo "WARNING: IGNORE_SIGNATURE=true; signature verification BYPASSED for $revision" >&2
      else
        ${lib.getExe verifyCommit} "$revision"
        echo "Signature verification passed: $revision" >&2
      fi

      new_ts="$(git show -s --format=%ct "$revision")"
      [[ "$new_ts" =~ ^[0-9]+$ ]]
      echo "Modified at: $(date -d @"$new_ts")" >&2

      if [[ "''${IGNORE_TIMESTAMP:-false}" == true ]]; then
        echo "WARNING: IGNORE_TIMESTAMP=true; freshness check BYPASSED" >&2
      elif ! [ "$new_ts" -gt "$current_ts" ]; then
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
        description = "HTTPS Git repository URL used for independent branch authorization.";
      };
      signingKeys = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = ''
          ASCII-armored OpenPGP public key files authorized to sign deployment
          commits, including their valid signing subkeys. Installed from the host
          configuration, never from CI or the candidate tree.
        '';
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
        assertion = cfg.signingKeys != [];
        message = "nixbotAutoUpgrade requires at least one pinned signing key.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.source;
        message = "nixbotAutoUpgrade source must use HTTPS.";
      }
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
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "nixbot-auto-upgrade";
        StateDirectoryMode = "0700";
      };

      script = "${lib.getExe cached-nixos-rebuild} ${cfg.operation} ${cfg.job}";
      startAt = cfg.dates;
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };
    system.build.verify-commit-signature = verifyCommit;
    system.build.cached-nixos-rebuild = cached-nixos-rebuild;
    environment.systemPackages = [cached-nixos-rebuild];
  };
}
